require "test_helper"

class Shiplog::Github::ClientTest < ActiveSupport::TestCase
  URL = "https://api.github.com/graphql".freeze

  def client = Shiplog::Github::Client.new(token: "tok", retry_delay: 0)

  test "sends bearer token and JSON body and returns data" do
    stub = stub_request(:post, URL)
      .with(headers: { "Authorization" => "Bearer tok", "User-Agent" => "shiplog/#{Shiplog::VERSION}" }) { |req|
        JSON.parse(req.body) == { "query" => "query { viewer { login } }", "variables" => { "a" => 1 } }
      }
      .to_return(body: { data: { viewer: { login: "ed" } } }.to_json)

    assert_equal({ "viewer" => { "login" => "ed" } }, client.query("query { viewer { login } }", { a: 1 }))
    assert_requested stub
  end

  test "raises Error with messages when response has errors" do
    stub_request(:post, URL).to_return(body: { errors: [ { message: "bad" }, { message: "worse" } ] }.to_json)

    error = assert_raises(Shiplog::Github::Error) { client.query("q") }
    assert_equal "bad; worse", error.message
  end

  test "raises RateLimited with reset_at on 403 with exhausted quota" do
    stub_request(:post, URL).to_return(status: 403, headers: { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => "1790000000" })

    error = assert_raises(Shiplog::Github::RateLimited) { client.query("q") }
    assert_equal Time.at(1_790_000_000), error.reset_at
  end

  test "raises RateLimited on 429" do
    stub_request(:post, URL).to_return(status: 429, headers: { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => "1790000000" })

    assert_raises(Shiplog::Github::RateLimited) { client.query("q") }
  end

  test "uses retry-after for secondary rate limits" do
    stub_request(:post, URL).to_return(status: 403, headers: { "retry-after" => "60" })

    travel_to Time.utc(2026, 10, 26, 12) do
      error = assert_raises(Shiplog::Github::RateLimited) { client.query("q") }
      assert_equal Time.utc(2026, 10, 26, 12, 1), error.reset_at
    end
  end

  test "a plain 403 is a generic Error" do
    stub_request(:post, URL).to_return(status: 403, headers: { "x-ratelimit-remaining" => "10" })

    error = assert_raises(Shiplog::Github::Error) { client.query("q") }
    assert_not_kind_of Shiplog::Github::RateLimited, error
  end

  test "retries once on 502 and then succeeds" do
    stub_request(:post, URL).to_return({ status: 502 }, { body: { data: { ok: true } }.to_json })

    assert_equal({ "ok" => true }, client.query("q"))
    assert_requested :post, URL, times: 2
  end

  test "gives up after one retry" do
    stub_request(:post, URL).to_return(status: 502)

    assert_raises(Shiplog::Github::Error) { client.query("q") }
    assert_requested :post, URL, times: 2
  end

  test "raises Error when no token is configured" do
    Shiplog.config.github_token = nil

    assert_raises(Shiplog::Github::Error) { Shiplog::Github::Client.new.query("q") }
    assert_not_requested :post, URL
  end

  test "default token comes from config callable" do
    Shiplog.config.github_token = -> { "from-config" }
    stub = stub_request(:post, URL).with(headers: { "Authorization" => "Bearer from-config" })
      .to_return(body: { data: {} }.to_json)

    Shiplog::Github::Client.new.query("q")
    assert_requested stub
  end

  test "queries include the required connections" do
    assert_includes Shiplog::Github::Queries::ISSUES, "closedByPullRequestsReferences(first: 20, includeClosedPrs: true)"
    assert_includes Shiplog::Github::Queries::PULL_REQUESTS, "closingIssuesReferences"
    assert_includes Shiplog::Github::Queries::COMMITS, "associatedPullRequests(first: 1)"
  end
end
