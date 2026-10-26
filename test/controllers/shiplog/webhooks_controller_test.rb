require "test_helper"

class Shiplog::WebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SECRET = "s3cret".freeze
  PATH = "/shiplog/github/webhook".freeze

  setup do
    Shiplog.config.repositories = %w[o/r o/other]
    Shiplog.config.webhook_secret = SECRET
  end

  def deliver(event, payload, id: SecureRandom.uuid, secret: SECRET, signature: :auto)
    body = payload.is_a?(String) ? payload : payload.to_json
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, body) if signature == :auto
    headers = { "CONTENT_TYPE" => "application/json", "X-GitHub-Event" => event, "X-GitHub-Delivery" => id }
    headers["X-Hub-Signature-256"] = signature if signature
    post PATH, params: body, headers: headers
  end

  def enqueued_refreshes
    enqueued_jobs.select { |j| j["job_class"] == "Shiplog::RefreshJob" }.map { |j| j["arguments"] }
  end

  test "issues event enqueues an issue refresh and records the delivery" do
    deliver "issues", { action: "opened", issue: { number: 7 }, repository: { full_name: "o/r" } }, id: "d-1"

    assert_response :accepted
    assert_equal [ [ "o/r", "issue", 7 ] ], enqueued_refreshes
    delivery = Shiplog::WebhookDelivery.find_by!(delivery_id: "d-1")
    assert_equal %w[issues opened o/r], [ delivery.event, delivery.action, delivery.repository_full_name ]
    assert delivery.received_at
    assert delivery.processed_at
    assert_nil delivery.error
  end

  test "pull_request event enqueues a pull_request refresh" do
    deliver "pull_request", { action: "closed", pull_request: { number: 9 }, repository: { full_name: "o/r" } }

    assert_response :accepted
    assert_equal [ [ "o/r", "pull_request", 9 ] ], enqueued_refreshes
  end

  test "sub_issue_added refreshes parent and child in their own repos" do
    deliver "sub_issues", {
      action: "sub_issue_added", repository: { full_name: "o/r" },
      parent_issue: { number: 1 }, sub_issue: { number: 2 }, sub_issue_repo: { full_name: "o/other" }
    }

    assert_response :accepted
    assert_equal [ [ "o/r", "issue", 1 ], [ "o/other", "issue", 2 ] ], enqueued_refreshes
  end

  test "parent_issue_removed refreshes child (payload repo) and parent (parent_issue_repo)" do
    deliver "sub_issues", {
      action: "parent_issue_removed", repository: { full_name: "o/r" },
      sub_issue: { number: 2 }, parent_issue: { number: 1 }, parent_issue_repo: { full_name: "o/other" }
    }

    assert_response :accepted
    assert_equal [ [ "o/r", "issue", 2 ], [ "o/other", "issue", 1 ] ].sort, enqueued_refreshes.sort
  end

  test "sub_issues ignores repositories that are not configured" do
    deliver "sub_issues", {
      action: "sub_issue_added", repository: { full_name: "o/r" },
      parent_issue: { number: 1 }, sub_issue: { number: 2 }, sub_issue_repo: { full_name: "x/unknown" }
    }

    assert_response :accepted
    assert_equal [ [ "o/r", "issue", 1 ] ], enqueued_refreshes
  end

  test "sub_issues dedupes identical targets within a delivery" do
    deliver "sub_issues", {
      action: "sub_issue_added", repository: { full_name: "o/r" },
      parent_issue: { number: 1 }, sub_issue: { number: 1 }, sub_issue_repo: { full_name: "o/r" }
    }

    assert_equal [ [ "o/r", "issue", 1 ] ], enqueued_refreshes
  end

  test "unconfigured repository is accepted without enqueueing" do
    deliver "issues", { action: "opened", issue: { number: 7 }, repository: { full_name: "x/unknown" } }

    assert_response :accepted
    assert_empty enqueued_refreshes
  end

  test "unhandled events are accepted without enqueueing" do
    deliver "push", { repository: { full_name: "o/r" } }

    assert_response :accepted
    assert_empty enqueued_refreshes
  end

  test "redelivery with the same delivery id is a no-op" do
    payload = { action: "opened", issue: { number: 7 }, repository: { full_name: "o/r" } }
    deliver "issues", payload, id: "d-2"
    deliver "issues", payload, id: "d-2"

    assert_response :accepted
    assert_equal 1, enqueued_refreshes.size
    assert_equal 1, Shiplog::WebhookDelivery.where(delivery_id: "d-2").count
  end

  test "bad signature is rejected and nothing is recorded" do
    deliver "issues", { action: "opened", issue: { number: 7 }, repository: { full_name: "o/r" } }, secret: "wrong"

    assert_response :unauthorized
    assert_equal 1, Shiplog::WebhookDelivery.count
    assert_empty enqueued_jobs
  end

  test "missing signature is rejected" do
    deliver "issues", { repository: { full_name: "o/r" } }, signature: nil

    assert_response :unauthorized
    assert_equal 1, Shiplog::WebhookDelivery.count
  end

  test "no webhook secret configured refuses the payload" do
    Shiplog.config.webhook_secret = nil
    deliver "issues", { action: "opened", issue: { number: 7 }, repository: { full_name: "o/r" } }

    assert_response :service_unavailable
    assert_empty enqueued_jobs
  end

  test "ping returns 200" do
    deliver "ping", { zen: "Keep it logically awesome." }

    assert_response :ok
  end

  test "malformed JSON with a valid signature is a 400" do
    deliver "issues", "{not json"

    assert_response :bad_request
    assert_equal 1, Shiplog::WebhookDelivery.count
  end

  test "bodies over 25 MB are refused before parsing" do
    post PATH, params: "x", headers: {
      "CONTENT_TYPE" => "application/json", "CONTENT_LENGTH" => (25.megabytes + 1).to_s,
      "X-GitHub-Event" => "issues", "X-GitHub-Delivery" => "big"
    }

    assert_response :content_too_large
    assert_equal 1, Shiplog::WebhookDelivery.count
  end

  test "enqueue failure stores the error and returns 500" do
    failing = Shiplog::RefreshJob.singleton_class
    failing.alias_method :original_perform_later, :perform_later
    failing.define_method(:perform_later) { |*| raise "queue down" }
    begin
      deliver "issues", { action: "opened", issue: { number: 7 }, repository: { full_name: "o/r" } }, id: "d-3"
    ensure
      failing.alias_method :perform_later, :original_perform_later
      failing.remove_method :original_perform_later
    end

    assert_response :internal_server_error
    assert_match "queue down", Shiplog::WebhookDelivery.find_by!(delivery_id: "d-3").error
  end

  test "controller is isolated from the host controllers and CSRF" do
    assert_equal ActionController::Base, Shiplog::WebhooksController.superclass
    assert_not Shiplog::WebhooksController._process_action_callbacks.any? { |c| c.filter == :verify_authenticity_token }
  end
end
