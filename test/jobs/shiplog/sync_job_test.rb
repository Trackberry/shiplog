require "test_helper"

class Shiplog::SyncJobTest < ActiveJob::TestCase
  URL = "https://api.github.com/graphql".freeze
  EMPTY_ISSUES = { data: { repository: { issues: { pageInfo: { hasNextPage: false }, nodes: [] } } } }.to_json
  EMPTY_PRS = { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false }, nodes: [] } } } }.to_json

  setup do
    Shiplog.config.github_token = "tok"
    Shiplog.config.repositories = [ "Acme/widgets", "Acme/gadgets" ]
  end

  def stub_repo(name, issues: EMPTY_ISSUES)
    stub_request(:post, URL).with { |req| body = JSON.parse(req.body); body.dig("variables", "name") == name && body["query"].include?("issues(first") }
      .to_return(body: issues)
    stub_request(:post, URL).with { |req| body = JSON.parse(req.body); body.dig("variables", "name") == name && body["query"].include?("pullRequests(first") }
      .to_return(body: EMPTY_PRS)
  end

  def count_drafter_calls
    calls = 0
    original = Shiplog::Drafter.method(:call)
    Shiplog::Drafter.define_singleton_method(:call) { calls += 1 }
    yield
    calls
  ensure
    Shiplog::Drafter.define_singleton_method(:call, original)
  end

  test "syncs repositories given as Hashes, including roadmap-only ones" do
    Shiplog.config.repositories = [ "Acme/widgets", { name: "Acme/gadgets", changelog: false, gem: "gadgets" } ]
    stub_repo("widgets")
    stub_repo("gadgets", issues: github_fixture("issues_page_2"))

    Shiplog::SyncJob.perform_now

    assert_equal 1, Shiplog::Repository.find_by!(full_name: "Acme/gadgets").issues.count
  end

  test "creates repositories, syncs each and then calls the drafter" do
    stub_repo("widgets", issues: github_fixture("issues_page_2"))
    stub_repo("gadgets")

    drafter_calls = count_drafter_calls { Shiplog::SyncJob.perform_now }

    assert_equal 1, drafter_calls
    assert_equal 1, Shiplog::Repository.find_by!(full_name: "Acme/widgets").issues.count
    assert Shiplog::Repository.find_by!(full_name: "Acme/gadgets").synced_at
  end

  test "one failing repository does not stop the others and the error is reported" do
    stub_request(:post, URL).with { |req| JSON.parse(req.body).dig("variables", "name") == "widgets" }
      .to_return(body: { errors: [ { message: "nope" } ] }.to_json)
    stub_repo("gadgets")
    reported = []
    subscriber = Struct.new(:reports) { def report(error, **) = reports << error }.new(reported)
    Rails.error.subscribe(subscriber)

    Shiplog::SyncJob.perform_now

    assert_equal [ "nope" ], reported.map(&:message)
    assert Shiplog::Repository.find_by!(full_name: "Acme/gadgets").synced_at
    assert_equal "nope", Shiplog::Repository.find_by!(full_name: "Acme/widgets").last_error
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  test "rate limiting re-enqueues the job at reset time" do
    reset = Time.utc(2026, 10, 26, 13)
    stub_request(:post, URL).to_return(status: 403, headers: { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => reset.to_i.to_s })

    assert_enqueued_with(job: Shiplog::SyncJob, at: reset + 1) do
      Shiplog::SyncJob.perform_now
    end
  end

  test "reports when the rate-limit retry cap is reached and raises" do
    reset = Time.utc(2026, 10, 26, 13)
    stub_request(:post, URL).to_return(status: 403, headers: { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => reset.to_i.to_s })
    reported = []
    subscriber = Struct.new(:reports) { def report(error, **) = reports << error }.new(reported)
    Rails.error.subscribe(subscriber)
    job = Shiplog::SyncJob.new
    job.executions = Shiplog::ApplicationJob::MAX_RATE_LIMIT_RETRIES

    assert_raises(Shiplog::Github::RateLimited) { job.perform_now }
    assert_equal 1, reported.size
    assert_kind_of Shiplog::Github::RateLimited, reported.first
  ensure
    Rails.error.unsubscribe(subscriber)
  end
end
