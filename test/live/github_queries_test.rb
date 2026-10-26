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

  test "COMMITS" do
    data = @client.query(Shiplog::Github::Queries::COMMITS, @vars)
    assert data.key?("repository")
  end
end
