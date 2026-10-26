require "test_helper"

class Shiplog::ScanChangesJobTest < ActiveJob::TestCase
  GRAPHQL = "https://api.github.com/graphql".freeze
  EMPTY_ISSUES = { data: { repository: { issues: { pageInfo: { hasNextPage: false }, nodes: [] } } } }.to_json
  EMPTY_PULLS = { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false }, nodes: [] } } } }.to_json

  def stub_marker(marker, body)
    stub_request(:post, GRAPHQL).with { |req| JSON.parse(req.body)["query"].include?(marker) }.to_return(body:)
  end

  def commit_requests = proc { |req| JSON.parse(req.body)["query"].include?("history") }

  setup do
    Shiplog.config.github_token = "tok"
    Shiplog.config.repositories = [ "Acme/widgets" ]
    stub_marker("issues(first", EMPTY_ISSUES)
    stub_marker("pullRequests(first", EMPTY_PULLS)
    stub_marker("history", github_fixture("commits"))
    travel_to Time.utc(2026, 10, 26, 12)
  end

  teardown { Rails.error.unsubscribe(@subscriber) if @subscriber }

  test "scans from seven days ago when never scanned and advances the window" do
    Shiplog::ScanChangesJob.perform_now

    repository = Shiplog::Repository.find_by!(full_name: "Acme/widgets")
    assert_equal Time.utc(2026, 10, 26, 12), repository.changes_scanned_at
    assert_requested(:post, GRAPHQL) { |req| commit_requests.call(req) && JSON.parse(req.body).dig("variables", "since") == "2026-10-19T12:00:00Z" }
  end

  test "scans from changes_scanned_at" do
    Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 10))

    Shiplog::ScanChangesJob.perform_now

    assert_requested(:post, GRAPHQL) { |req| commit_requests.call(req) && JSON.parse(req.body).dig("variables", "since") == "2026-10-10T00:00:00Z" }
  end

  test "drafts change entries for candidates and enqueues rewrites" do
    repository = Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 1))
    pr = repository.pull_requests.create!(node_id: "PR_x", number: 5, title: "Add thing", state: "merged", merged_at: Time.utc(2026, 10, 15, 9),
      author_login: "ed", labels: [], github_updated_at: Time.utc(2026, 10, 15))

    Shiplog::ScanChangesJob.perform_now

    pr_entry = pr.entries.find_by!(kind: "change")
    assert_enqueued_with(job: Shiplog::RewriteEntryJob, args: [ pr_entry.id ])
    assert pr_entry.draft?
    assert_equal Date.new(2026, 10, 15), pr_entry.released_on
    commit = repository.commits.find_by!(sha: "a" * 40)
    assert_enqueued_with(job: Shiplog::RewriteEntryJob, args: [ commit.entries.find_by!(kind: "change").id ])
    assert_equal Date.new(2026, 10, 12), commit.entries.find_by!(kind: "change").released_on
    assert_not repository.commits.find_by!(sha: "c" * 40).entries.exists?
  end

  test "a bot's gem upgrade gets one change entry dated at its merge, and the gem repository drafts none of its own" do
    Shiplog.config.repositories = [ "Acme/widgets", { name: "Acme/gadgets", changelog: false, gem: "gadgets" } ]
    host = Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 1))
    gem_repo = Shiplog::Repository.create!(full_name: "Acme/gadgets", changes_scanned_at: Time.utc(2026, 10, 1))
    bump = host.pull_requests.create!(node_id: "PR_bump", number: 7, title: "chore(deps): Bump gadgets from 1.0 to 1.1", state: "merged",
      merged_at: Time.utc(2026, 10, 18, 9), author_login: "dependabot[bot]", labels: [ "dependencies" ], github_updated_at: Time.utc(2026, 10, 18))
    Shiplog::PullRequestUpgrade.create!(pull_request: bump, gem_name: "gadgets", from_ref: "v1.0", to_ref: "v1.1", gem_repository: "Acme/gadgets",
      gem_changes: [ { "number" => 3, "title" => "Faster gadgets", "body_excerpt" => "", "url" => "u" } ])
    gem_repo.pull_requests.create!(node_id: "PR_gadgets_3", number: 3, title: "Faster gadgets", state: "merged", merged_at: Time.utc(2026, 10, 10),
      author_login: "ed", labels: [], github_updated_at: Time.utc(2026, 10, 10))

    Shiplog::ScanChangesJob.perform_now

    entry = bump.entries.find_by!(kind: "change")
    assert_equal Date.new(2026, 10, 18), entry.released_on
    assert_equal 0, Shiplog::Entry.change.where(subject: gem_repo.pull_requests).count
    assert_equal 1, Shiplog::Entry.change.where(subject_type: "Shiplog::PullRequest", subject_id: host.pull_requests.select(:id)).count
  end

  test "a changelog: false repository is synced but never drafts changes" do
    Shiplog.config.repositories = [ { name: "Acme/widgets", changelog: false } ]
    repository = Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 1))
    repository.pull_requests.create!(node_id: "PR_x", number: 5, title: "Add thing", state: "merged", merged_at: Time.utc(2026, 10, 15, 9),
      author_login: "ed", labels: [], github_updated_at: Time.utc(2026, 10, 15))

    assert_no_difference -> { Shiplog::Entry.change.count } do
      Shiplog::ScanChangesJob.perform_now
    end

    assert_not_requested(:post, GRAPHQL) { |req| commit_requests.call(req) }
    assert_requested(:post, GRAPHQL) { |req| JSON.parse(req.body)["query"].include?("issues(first") }
    assert_equal Time.utc(2026, 10, 26, 12), repository.reload.changes_scanned_at
  end

  test "is idempotent" do
    Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 1))
    Shiplog::ScanChangesJob.perform_now

    errors = []
    @subscriber = Class.new { define_method(:report) { |error, **| errors << error } }.new
    Rails.error.subscribe(@subscriber)

    travel_to Time.utc(2026, 10, 27, 12)
    assert_no_difference -> { Shiplog::Entry.change.count } do
      Shiplog::ScanChangesJob.perform_now
    end

    assert_empty errors
    assert_equal Time.utc(2026, 10, 27, 12), Shiplog::Repository.find_by!(full_name: "Acme/widgets").changes_scanned_at
  end

  test "drafts a PR merged before the scan that was only imported by the in-job sync" do
    repository = Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 20))
    late = JSON.parse(github_fixture("pull_requests"))
    node = late.dig("data", "repository", "pullRequests", "nodes", 0)
    node.merge!("mergedAt" => "2026-10-25T09:00:00Z", "updatedAt" => "2026-10-25T09:00:00Z", "closingIssuesReferences" => { "nodes" => [] },
      "labels" => { "nodes" => [] })
    late["data"]["repository"]["pullRequests"].merge!("nodes" => [ node ], "pageInfo" => { "hasNextPage" => false })
    stub_marker("pullRequests(first", late.to_json)

    Shiplog::ScanChangesJob.perform_now

    pull_request = repository.pull_requests.find_by!(node_id: node["id"])
    assert pull_request.entries.exists?(kind: "change")
  end

  test "runs the drafter once after all repositories" do
    Shiplog.config.repositories = [ "Acme/widgets", "Acme/gadgets" ]
    calls = []
    original = Shiplog::Drafter.method(:call)
    Shiplog::Drafter.define_singleton_method(:call) { calls << Shiplog::Repository.where.not(changes_scanned_at: nil).count }

    Shiplog::ScanChangesJob.perform_now

    assert_equal [ 2 ], calls
  ensure
    Shiplog::Drafter.define_singleton_method(:call, original)
  end

  test "advances the window even with no candidates" do
    stub_marker("history", { data: { repository: { defaultBranchRef: nil } } }.to_json)
    assert_no_difference -> { Shiplog::Entry.change.count } do
      Shiplog::ScanChangesJob.perform_now
    end

    assert_equal Time.utc(2026, 10, 26, 12), Shiplog::Repository.find_by!(full_name: "Acme/widgets").changes_scanned_at
  end

  test "keeps the window and continues when one repository fails" do
    Shiplog.config.repositories = [ "Acme/widgets", "Acme/gadgets" ]
    stub_request(:post, GRAPHQL).with { |req| JSON.parse(req.body).dig("variables", "name") == "widgets" }
      .to_return(status: 500, body: "boom")
    { "issues(first" => EMPTY_ISSUES, "pullRequests(first" => EMPTY_PULLS, "history" => github_fixture("commits") }.each do |marker, body|
      stub_request(:post, GRAPHQL).with { |req| JSON.parse(req.body).dig("variables", "name") == "gadgets" && JSON.parse(req.body)["query"].include?(marker) }
        .to_return(body:)
    end

    Shiplog::ScanChangesJob.perform_now

    assert_nil Shiplog::Repository.find_by!(full_name: "Acme/widgets").changes_scanned_at
    assert Shiplog::Repository.find_by!(full_name: "Acme/gadgets").changes_scanned_at
  end
end
