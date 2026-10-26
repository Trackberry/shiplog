require "test_helper"

# Opt-in: runs every query against the real GitHub API.
#   SHIPLOG_LIVE_GITHUB=1 GITHUB_TOKEN=... [SHIPLOG_LIVE_REPO=owner/name] bin/rails test test/live
class LiveGithubQueriesTest < ActiveSupport::TestCase
  setup do
    skip "set SHIPLOG_LIVE_GITHUB=1 to run live GitHub checks" unless ENV["SHIPLOG_LIVE_GITHUB"]
    WebMock.allow_net_connect!
    owner, name = ENV.fetch("SHIPLOG_LIVE_REPO", "Trackberry/shiplog").split("/", 2)
    @vars = { owner:, name: }
    @client = Shiplog::Github::Client.new(token: ENV.fetch("GITHUB_TOKEN"))
  end

  teardown { WebMock.disable_net_connect! }

  test "ISSUES" do
    data = @client.query(Shiplog::Github::Queries::ISSUES, @vars)
    assert data.dig("repository", "issues", "nodes")
  end

  test "PULL_REQUESTS" do
    data = @client.query(Shiplog::Github::Queries::PULL_REQUESTS, @vars)
    assert data.dig("repository", "pullRequests", "nodes")
  end

  test "ISSUE" do
    data = @client.query(Shiplog::Github::Queries::ISSUE, @vars.merge(number: 1))
    assert data.key?("repository")
  end

  test "PULL_REQUEST (NOT_FOUND is fine)" do
    data = @client.query(Shiplog::Github::Queries::PULL_REQUEST, @vars.merge(number: 1))
    assert data.key?("repository")
  end

  test "PULL_REQUESTS return the upgrade-detection fields" do
    data = @client.query(Shiplog::Github::Queries::PULL_REQUESTS, @vars)
    node = data.dig("repository", "pullRequests", "nodes").find { |pr| pr["state"] == "MERGED" }
    skip "no merged pull request in #{@vars.values.join("/")}" unless node
    assert node.key?("baseRefOid")
    assert node.dig("mergeCommit", "oid")
    assert node.dig("mergeCommit", "parents", "nodes").is_a?(Array)
    assert node.dig("mergeCommit", "parents", "nodes", 0, "oid")
    assert_includes [ true, false ], node.dig("files", "pageInfo", "hasNextPage")
    assert node["files"]["nodes"].is_a?(Array)
  end

  test "BLOB_TEXT reads a file at a commit, and null when it is absent" do
    oid = @client.query(Shiplog::Github::Queries::COMMITS, @vars).dig("repository", "defaultBranchRef", "target", "history", "nodes", 0, "oid")
    skip "no commits" unless oid
    present = @client.query(Shiplog::Github::Queries::BLOB_TEXT, @vars.merge(expression: "#{oid}:README.md"))
    assert present.dig("repository", "object", "text").is_a?(String)
    absent = @client.query(Shiplog::Github::Queries::BLOB_TEXT, @vars.merge(expression: "#{oid}:no/such/file"))
    assert_nil absent.dig("repository", "object")
  end

  test "COMMIT_PULL_REQUESTS resolves associated pull requests for commit node ids" do
    commit = @client.get("/repos/#{@vars[:owner]}/#{@vars[:name]}/commits?per_page=1").first
    skip "no commits" unless commit
    data = @client.query(Shiplog::Github::Queries::COMMIT_PULL_REQUESTS, ids: [ commit["node_id"] ])
    assert_equal commit["sha"], data.dig("nodes", 0, "oid")
    assert data.dig("nodes", 0, "associatedPullRequests", "nodes").is_a?(Array)
  end

  test "REST compare lists commits with node ids" do
    owner, name = @vars.values_at(:owner, :name)
    commits = @client.get("/repos/#{owner}/#{name}/commits?per_page=2")
    skip "need two commits" if commits.size < 2
    compare = @client.get("/repos/#{owner}/#{name}/compare/#{commits.last["sha"]}...#{commits.first["sha"]}")
    assert compare["commits"].first.key?("node_id")
  end

  test "BODY_HTML returns the rendered body of an issue or pull request" do
    node = @client.query(Shiplog::Github::Queries::ISSUES, @vars).dig("repository", "issues", "nodes", 0)
    skip "no issues in #{@vars.values.join("/")}" unless node
    data = @client.query(Shiplog::Github::Queries::BODY_HTML, id: node["id"])
    assert data.dig("node", "bodyHTML").is_a?(String)

    pull_request = @client.query(Shiplog::Github::Queries::PULL_REQUESTS, @vars).dig("repository", "pullRequests", "nodes", 0)
    skip "no pull requests" unless pull_request
    assert @client.query(Shiplog::Github::Queries::BODY_HTML, id: pull_request["id"]).dig("node", "bodyHTML").is_a?(String)
  end

  test "COMMITS" do
    data = @client.query(Shiplog::Github::Queries::COMMITS, @vars)
    assert data.key?("repository")
  end
end
