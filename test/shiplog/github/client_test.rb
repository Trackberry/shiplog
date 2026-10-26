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

  test "returns data when all errors are NOT_FOUND" do
    body = { data: { repository: { issue: nil } }, errors: [ { type: "NOT_FOUND", path: %w[repository issue], message: "nope" } ] }
    stub_request(:post, URL).to_return(body: body.to_json)

    assert_equal({ "repository" => { "issue" => nil } }, client.query("q"))
  end

  test "raises when NOT_FOUND is mixed with other errors" do
    body = { data: { repository: nil }, errors: [ { type: "NOT_FOUND", message: "a" }, { type: "OTHER", message: "b" } ] }
    stub_request(:post, URL).to_return(body: body.to_json)

    assert_raises(Shiplog::Github::Error) { client.query("q") }
  end

  test "raises when NOT_FOUND comes without data" do
    stub_request(:post, URL).to_return(body: { errors: [ { type: "NOT_FOUND", message: "a" } ] }.to_json)

    assert_raises(Shiplog::Github::Error) { client.query("q") }
  end

  test "wraps network errors in Transient" do
    [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError, SocketError ].each do |klass|
      stub_request(:post, URL).to_raise(klass)

      error = assert_raises(Shiplog::Github::Transient, klass.name) { client.query("q") }
      assert_kind_of Shiplog::Github::Error, error
    end
  end

  test "5xx after retry raises Transient" do
    stub_request(:post, URL).to_return(status: 503)

    assert_raises(Shiplog::Github::Transient) { client.query("q") }
  end

  test "RATE_LIMITED GraphQL error on HTTP 200 raises RateLimited using the reset header" do
    body = { errors: [ { type: "RATE_LIMITED", message: "API rate limit exceeded" } ] }
    stub_request(:post, URL).to_return(body: body.to_json, headers: { "x-ratelimit-reset" => "1790000000" })

    error = assert_raises(Shiplog::Github::RateLimited) { client.query("q") }
    assert_equal Time.at(1_790_000_000), error.reset_at
  end

  test "missing reset header defaults reset_at to 60 seconds from now" do
    body = { errors: [ { type: "RATE_LIMITED", message: "x" } ] }
    stub_request(:post, URL).to_return(body: body.to_json)

    travel_to Time.utc(2026, 10, 26, 12) do
      error = assert_raises(Shiplog::Github::RateLimited) { client.query("q") }
      assert_equal Time.utc(2026, 10, 26, 12, 1), error.reset_at
    end
  end

  test "403 without reset header or retry-after defaults reset_at to 60 seconds from now" do
    stub_request(:post, URL).to_return(status: 403, headers: { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => "0" })

    travel_to Time.utc(2026, 10, 26, 12) do
      error = assert_raises(Shiplog::Github::RateLimited) { client.query("q") }
      assert_equal Time.utc(2026, 10, 26, 12, 1), error.reset_at
    end
  end

  test "get sends the bearer token to the REST API and returns the parsed body" do
    stub = stub_request(:get, "https://api.github.com/repos/o/r/compare/a...b")
      .with(headers: { "Authorization" => "Bearer tok", "Accept" => "application/vnd.github+json", "User-Agent" => "shiplog/#{Shiplog::VERSION}" })
      .to_return(body: { commits: [ { sha: "1" } ] }.to_json)

    assert_equal({ "commits" => [ { "sha" => "1" } ] }, client.get("/repos/o/r/compare/a...b"))
    assert_requested stub
  end

  test "get raises NotFound on 404" do
    stub_request(:get, "https://api.github.com/repos/o/r/compare/a...b").to_return(status: 404, body: "{}")

    error = assert_raises(Shiplog::Github::NotFound) { client.get("/repos/o/r/compare/a...b") }
    assert_kind_of Shiplog::Github::Error, error
  end

  test "get raises RateLimited, Transient and Error like query" do
    url = "https://api.github.com/repos/o/r"
    stub_request(:get, url).to_return(status: 403, headers: { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => "1790000000" })
    assert_equal Time.at(1_790_000_000), assert_raises(Shiplog::Github::RateLimited) { client.get("/repos/o/r") }.reset_at

    stub_request(:get, url).to_return({ status: 502 }, { body: { ok: true }.to_json })
    assert_equal({ "ok" => true }, client.get("/repos/o/r"))

    stub_request(:get, url).to_return(status: 503)
    assert_raises(Shiplog::Github::Transient) { client.get("/repos/o/r") }

    stub_request(:get, url).to_raise(Net::ReadTimeout)
    assert_raises(Shiplog::Github::Transient) { client.get("/repos/o/r") }

    stub_request(:get, url).to_return(status: 403, headers: { "x-ratelimit-remaining" => "10" })
    assert_raises(Shiplog::Github::Error) { client.get("/repos/o/r") }

    stub_request(:get, url).to_return(body: "<html>")
    assert_raises(Shiplog::Github::Error) { client.get("/repos/o/r") }
  end

  test "get raises Error when no token is configured" do
    assert_raises(Shiplog::Github::Error) { Shiplog::Github::Client.new(token: nil).get("/repos/o/r") }
    assert_not_requested :get, "https://api.github.com/repos/o/r"
  end
end
