require "test_helper"

class Shiplog::RefreshJobTest < ActiveJob::TestCase
  URL = "https://api.github.com/graphql".freeze

  setup do
    Shiplog.config.github_token = "tok"
    Shiplog.config.repositories = [ "Acme/widgets" ]
  end

  test "fetches a single issue, imports it and runs the drafter" do
    stub = stub_request(:post, URL).with { |req|
      vars = JSON.parse(req.body)["variables"]
      vars.slice("owner", "name", "number") == { "owner" => "Acme", "name" => "widgets", "number" => 12 }
    }.to_return(body: github_fixture("issue_single"))
    drafted = false
    original = Shiplog::Drafter.method(:call)
    Shiplog::Drafter.define_singleton_method(:call) { drafted = true }

    Shiplog::RefreshJob.perform_now("Acme/widgets", "issue", 12)

    assert_requested stub
    assert_equal "Issue 1 title", Shiplog::Issue.find_by!(node_id: "I_kwDOSync001").title
    assert Shiplog::IssueLink.exists?(issue_node_id: "I_kwDOSync001", pull_request_node_id: "PR_kwDOSync103")
    assert drafted
  ensure
    Shiplog::Drafter.define_singleton_method(:call, original)
  end

  test "matches the configured repository case-insensitively" do
    stub = stub_request(:post, URL).with { |req|
      JSON.parse(req.body)["variables"].slice("owner", "name") == { "owner" => "Acme", "name" => "widgets" }
    }.to_return(body: github_fixture("issue_single"))

    Shiplog::RefreshJob.perform_now("acme/Widgets", "issue", 12)

    assert_requested stub
    assert_equal [ "Acme/widgets" ], Shiplog::Repository.where(full_name: %w[Acme/widgets acme/Widgets]).pluck(:full_name)
  end

  test "fetches a single pull request" do
    stub_request(:post, URL).to_return(body: github_fixture("pull_request_single"))

    Shiplog::RefreshJob.perform_now("Acme/widgets", "pull_request", 12)

    assert_equal "merged", Shiplog::PullRequest.find_by!(node_id: "PR_kwDOSync103").state
  end

  test "a missing issue (data null plus NOT_FOUND error) is a no-op" do
    body = {
      data: { repository: { issue: nil } },
      errors: [ { type: "NOT_FOUND", path: %w[repository issue], locations: [ { line: 3, column: 5 } ], message: "Could not resolve to an Issue with the number of 99." } ]
    }
    stub_request(:post, URL).to_return(body: body.to_json)

    assert_no_difference -> { Shiplog::Issue.count } do
      assert_nothing_raised { Shiplog::RefreshJob.perform_now("Acme/widgets", "issue", 99) }
    end
  end

  def not_found_body
    {
      data: { repository: { issue: nil } },
      errors: [ { type: "NOT_FOUND", path: %w[repository issue], locations: [ { line: 3, column: 5 } ], message: "Could not resolve to an Issue." } ]
    }.to_json
  end

  def local_issue(number: 40, node_id: "I_gone", labels: [ "public" ])
    repository = Shiplog::Repository.find_or_create_by!(full_name: "Acme/widgets")
    issue = repository.issues.create!(node_id:, number:, title: "Gone", body: "b", state: "open", labels:, assignees_count: 0,
      url: "https://github.com/Acme/widgets/issues/#{number}", github_created_at: 1.day.ago, github_updated_at: 1.day.ago)
    issue.entries.create!(kind: "roadmap", status: "approved", title: "Gone", body: "b", approved_at: 1.hour.ago, approved_by: "ed")
    issue
  end

  test "a null issue closes the local row as deleted, keeping it and its entries" do
    issue = local_issue
    stub_request(:post, URL).to_return(body: not_found_body)

    Shiplog::RefreshJob.perform_now("Acme/widgets", "issue", 40)

    issue.reload
    assert_equal %w[closed deleted], [ issue.state, issue.state_reason ]
    assert_equal 1, issue.entries.count
    assert_not_includes Shiplog::Roadmap.new(published_only: false).items.map(&:issue), issue
  end

  test "a deleted issue never gets a feature draft" do
    issue = local_issue
    stub_request(:post, URL).to_return(body: not_found_body)

    Shiplog::RefreshJob.perform_now("Acme/widgets", "issue", 40)

    assert_not issue.entries.exists?(kind: "feature")
  end

  test "closing a deleted issue leaves a missing local row alone" do
    stub_request(:post, URL).to_return(body: not_found_body)
    assert_nothing_raised { Shiplog::RefreshJob.perform_now("Acme/widgets", "issue", 41) }
  end

  test "a transferred issue returned under a different node closes the old local row" do
    issue = local_issue(number: 12, node_id: "I_old")
    stub_request(:post, URL).to_return(body: github_fixture("issue_single"))

    Shiplog::RefreshJob.perform_now("Acme/widgets", "issue", 12)

    assert_equal %w[closed deleted], [ issue.reload.state, issue.state_reason ]
    assert Shiplog::Issue.exists?(node_id: "I_kwDOSync001")
  end

  test "an unchanged node id does not close the local row" do
    issue = local_issue(number: 1, node_id: "I_kwDOSync001")
    stub_request(:post, URL).to_return(body: github_fixture("issue_single"))

    Shiplog::RefreshJob.perform_now("Acme/widgets", "issue", 1)

    assert_equal "open", issue.reload.state
  end

  test "ignores repositories that are not configured" do
    assert_no_difference -> { Shiplog::Repository.count } do
      Shiplog::RefreshJob.perform_now("Other/repo", "issue", 1)
    end
    assert_not_requested :post, URL
  end

  test "retries transient failures with backoff" do
    stub_request(:post, URL).to_raise(Net::ReadTimeout)

    assert_enqueued_with(job: Shiplog::RefreshJob) do
      Shiplog::RefreshJob.perform_now("Acme/widgets", "issue", 12)
    end
  end

  test "rejects unknown kinds" do
    assert_raises(ArgumentError) { Shiplog::RefreshJob.perform_now("Acme/widgets", "commit", 1) }
  end
end
