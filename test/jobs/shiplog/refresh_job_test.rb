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
