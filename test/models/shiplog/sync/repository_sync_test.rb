require "test_helper"

class Shiplog::Sync::RepositorySyncTest < ActiveSupport::TestCase
  URL = "https://api.github.com/graphql".freeze
  EMPTY_PULLS = { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false }, nodes: [] } } } }.to_json

  setup do
    @repository = Shiplog::Repository.create!(full_name: "Acme/widgets")
    @client = Shiplog::Github::Client.new(token: "tok")
  end

  def sync = Shiplog::Sync::RepositorySync.new(@repository, client: @client)

  def stub_graphql(query_marker, *bodies)
    stub_request(:post, URL).with { |req| JSON.parse(req.body)["query"].include?(query_marker) }
      .to_return(*bodies.map { |body| { body: } })
  end

  def stub_issues_and_prs
    @issues = stub_graphql("issues(first", github_fixture("issues_page_1"), github_fixture("issues_page_2"))
    @pulls = stub_graphql("pullRequests(first", github_fixture("pull_requests"), EMPTY_PULLS)
  end

  def lock(version) = "GEM\n  remote: https://rubygems.pkg.github.com/Acme/\n  specs:\n    gadgets (#{version})\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  gadgets\n"

  def stub_gadgets_upgrade
    Shiplog.config.repositories = [ "Acme/widgets", { name: "Acme/gadgets", changelog: false, gem: "gadgets" } ]
    { "base1" => "1.0.0", "merge1" => "1.1.0" }.each do |oid, version|
      stub_request(:post, URL).with { |req| JSON.parse(req.body).dig("variables", "expression") == "#{oid}:Gemfile.lock" }
        .to_return(body: { data: { repository: { object: { text: lock(version) } } } }.to_json)
    end
    stub_request(:get, "https://api.github.com/repos/Acme/gadgets/compare/v1.0.0...v1.1.0").with(query: { per_page: 100, page: 1 }).to_return(body: { commits: [ { node_id: "C1" } ] }.to_json)
    stub_request(:post, URL).with { |req| JSON.parse(req.body).dig("variables", "ids") == [ "C1" ] }.to_return(body: { data: { nodes: [
      { oid: "c1", associatedPullRequests: { nodes: [ { number: 3, title: "Faster gadgets", body: "b", url: "u", state: "MERGED",
                                                      repository: { nameWithOwner: "Acme/gadgets" } } ] } }
    ] } }.to_json)
  end

  def with_lockfile_files(body)
    JSON.parse(body).tap do |page|
      page.dig("data", "repository", "pullRequests", "nodes").first.merge!(
        "baseRefOid" => "stale", "mergeCommit" => { "oid" => "merge1", "parents" => { "nodes" => [ { "oid" => "base1" } ] } }, "files" => { "nodes" => [ { "path" => "Gemfile.lock" } ] }
      )
    end.to_json
  end

  test "detects gem upgrades in the merged pull requests it imports" do
    stub_gadgets_upgrade
    stub_graphql("issues(first", github_fixture("issues_page_2"))
    stub_graphql("pullRequests(first", with_lockfile_files(github_fixture("pull_requests")), EMPTY_PULLS)

    sync.call

    upgrade = @repository.pull_requests.find_by!(number: 12).upgrades.sole
    assert_equal [ "gadgets", "v1.0.0", "v1.1.0" ], [ upgrade.gem_name, upgrade.from_ref, upgrade.to_ref ]
    assert_equal [ 3 ], upgrade.gem_changes.map { |change| change["number"] }
  end

  def stub_failing_detection(error)
    stub_gadgets_upgrade
    stub_graphql("issues(first", github_fixture("issues_page_2"))
    stub_graphql("pullRequests(first", with_lockfile_files(github_fixture("pull_requests")), EMPTY_PULLS)
    stub_request(:post, URL).with { |req| JSON.parse(req.body).dig("variables", "expression") == "base1:Gemfile.lock" }.to_raise(error)
  end

  test "an unexpected detector error does not fail the sync: the cursor and synced_at are saved and the error is logged" do
    stub_failing_detection(RuntimeError.new("boom"))
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)

    begin
      sync.call
    ensure
      Rails.logger = original
    end

    @repository.reload
    assert @repository.sync_cursor
    assert @repository.synced_at
    assert_nil @repository.last_error
    assert_match(/boom/, io.string)
  end

  test "a transient detector error is re-raised only after the cursor is saved" do
    stub_failing_detection(Net::ReadTimeout)

    assert_raises(Shiplog::Github::Transient) { sync.call }

    @repository.reload
    assert @repository.sync_cursor
    assert @repository.synced_at
  end

  test "a rate-limited detector is re-raised only after the cursor is saved" do
    stub_gadgets_upgrade
    stub_graphql("issues(first", github_fixture("issues_page_2"))
    stub_graphql("pullRequests(first", with_lockfile_files(github_fixture("pull_requests")), EMPTY_PULLS)
    stub_request(:post, URL).with { |req| JSON.parse(req.body).dig("variables", "expression") == "base1:Gemfile.lock" }
      .to_return(status: 429, headers: { "retry-after" => "30" })

    assert_raises(Shiplog::Github::RateLimited) { sync.call }

    assert @repository.reload.sync_cursor
  end

  test "does not detect upgrades in a changelog: false repository" do
    stub_gadgets_upgrade
    Shiplog.config.repositories = [ { name: "Acme/widgets", changelog: false }, { name: "Acme/gadgets", changelog: false, gem: "gadgets" } ]
    stub_graphql("issues(first", github_fixture("issues_page_2"))
    stub_graphql("pullRequests(first", with_lockfile_files(github_fixture("pull_requests")), EMPTY_PULLS)

    sync.call

    assert_not_requested(:post, URL) { |req| JSON.parse(req.body).dig("variables", "expression") }
    assert_equal 0, Shiplog::PullRequestUpgrade.count
  end

  test "pages through issues and imports every node" do
    stub_issues_and_prs

    sync.call

    assert_requested @issues, times: 2
    assert_equal [ 1, 2, 3 ], @repository.issues.order(:number).pluck(:number)
    assert_requested(:post, URL, times: 1) { |req| JSON.parse(req.body)["variables"]["after"] == "Y3Vyc29yOnYyOpHOAAAB" && req.body.include?("issues(first") }
  end

  test "first run backfills all pull requests, sets cursor and synced_at, clears the error" do
    stub_graphql("issues(first", github_fixture("issues_page_2"))
    @pulls = stub_graphql("pullRequests(first", github_fixture("pull_requests"), EMPTY_PULLS)
    @repository.update!(last_error: "boom")

    travel_to(Time.utc(2026, 10, 26, 12)) { sync.call }

    assert_requested @pulls, times: 2
    assert_equal 3, @repository.pull_requests.count
    assert_equal Time.utc(2026, 10, 20, 9, 55), @repository.reload.sync_cursor
    assert_equal Time.utc(2026, 10, 26, 12), @repository.synced_at
    assert_nil @repository.last_error
  end

  test "imports pull requests only until updatedAt falls below the cursor" do
    @repository.update!(sync_cursor: Time.utc(2026, 10, 5))
    @issues = stub_graphql("issues(first", github_fixture("issues_page_2"))
    @pulls = stub_graphql("pullRequests(first", github_fixture("pull_requests"))

    sync.call

    assert_requested @pulls, times: 1
    assert_equal %w[PR_kwDOSync103 PR_kwDOSync104], @repository.pull_requests.order(:number).pluck(:node_id)
  end

  test "passes the cursor as since to the issues query" do
    @repository.update!(sync_cursor: Time.utc(2026, 10, 5))
    stub_graphql("issues(first", github_fixture("issues_page_2"))
    stub_graphql("pullRequests(first", github_fixture("pull_requests"))

    sync.call

    assert_requested(:post, URL) { |req| JSON.parse(req.body).dig("variables", "since")&.start_with?("2026-10-05T00:00:00") }
  end

  test "skips issue nodes that are pull requests" do
    page = JSON.parse(github_fixture("issues_page_2"))
    page.dig("data", "repository", "issues", "nodes", 0)["__typename"] = "PullRequest"
    stub_graphql("issues(first", page.to_json)
    stub_graphql("pullRequests(first", EMPTY_PULLS)

    sync.call

    assert_equal 0, @repository.issues.count
  end

  test "stores last_error and re-raises on Github::Error" do
    stub_request(:post, URL).to_return(body: { errors: [ { message: "Could not resolve" } ] }.to_json)

    assert_raises(Shiplog::Github::Error) { sync.call }

    assert_equal "Could not resolve", @repository.reload.last_error
    assert_nil @repository.synced_at
  end

  test "cursor is the earlier of newest-seen and sync start, minus a safety window" do
    page = JSON.parse(github_fixture("issues_page_2"))
    stub_graphql("issues(first", page.to_json)
    pulls = JSON.parse(github_fixture("pull_requests"))
    pulls.dig("data", "repository", "pullRequests", "pageInfo")["hasNextPage"] = false
    pulls.dig("data", "repository", "pullRequests", "nodes", 0)["updatedAt"] = "2026-10-26T12:00:30Z"
    stub_graphql("pullRequests(first", pulls.to_json)

    travel_to(Time.utc(2026, 10, 26, 12)) { sync.call }

    assert_equal Time.utc(2026, 10, 26, 11, 55), @repository.reload.sync_cursor
  end

  test "cursor never moves backwards" do
    @repository.update!(sync_cursor: Time.utc(2026, 10, 26, 11, 59))
    stub_graphql("issues(first", { data: { repository: { issues: { pageInfo: { hasNextPage: false }, nodes: [] } } } }.to_json)
    stub_graphql("pullRequests(first", EMPTY_PULLS)

    travel_to(Time.utc(2026, 10, 26, 12)) { sync.call }

    assert_equal Time.utc(2026, 10, 26, 11, 59), @repository.reload.sync_cursor
  end

  test "ignores null nodes" do
    page = JSON.parse(github_fixture("issues_page_2"))
    page.dig("data", "repository", "issues", "nodes").unshift(nil)
    stub_graphql("issues(first", page.to_json)
    stub_graphql("pullRequests(first", EMPTY_PULLS)

    assert_nothing_raised { sync.call }
  end

  test "stores last_error for transient network failures" do
    stub_request(:post, URL).to_raise(Net::ReadTimeout)

    assert_raises(Shiplog::Github::Transient) { sync.call }

    assert_match(/Net::ReadTimeout/, @repository.reload.last_error)
  end

  test "stores last_error and re-raises unexpected errors" do
    stub_graphql("issues(first", { data: { repository: { issues: { pageInfo: { hasNextPage: false }, nodes: [ { "id" => "x", "updatedAt" => "garbage", "__typename" => "Issue" } ] } } } }.to_json)

    assert_raises(StandardError) { sync.call }

    assert @repository.reload.last_error.present?
  end
end
