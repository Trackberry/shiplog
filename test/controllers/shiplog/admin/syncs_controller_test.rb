require "test_helper"

class Shiplog::Admin::SyncsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Shiplog.config.repositories = [ "Trackberry/trackberry", "Trackberry/unsynced" ]
    Shiplog.config.webhook_secret = "secret"
    Shiplog.config.github_token = "token"
  end

  test "lists configured repositories with sync state" do
    shiplog_repositories(:app).update!(synced_at: Time.utc(2026, 10, 20, 8), last_error: "Bad credentials", changes_scanned_at: Time.utc(2026, 10, 19, 8))
    get "/admin/shiplog/sync"
    assert_response :ok
    assert_select "tr.shiplog-repository-row", 2
    assert_select "tr.shiplog-repository-row", text: /Trackberry\/trackberry\b.*Bad credentials/m
    assert_select "tr.shiplog-repository-row", text: /Trackberry\/unsynced.*Never/m
    assert_no_difference -> { Shiplog::Repository.count } do
      get "/admin/shiplog/sync"
    end
  end

  test "lists repositories configured as Hashes" do
    Shiplog.config.repositories = [ "Trackberry/trackberry", { name: "Trackberry/market_data", changelog: false, gem: "market_data" } ]
    get "/admin/shiplog/sync"
    assert_select "tr.shiplog-repository-row", 2
    assert_select "tr.shiplog-repository-row", text: /Trackberry\/market_data/
  end

  test "lists the 20 most recent webhook deliveries" do
    25.times do |i|
      Shiplog::WebhookDelivery.create!(delivery_id: "d-#{i}", event: "issues", action: "edited", repository_full_name: "Trackberry/trackberry",
        received_at: Time.utc(2026, 10, 13) + i.hours, error: (i == 24 ? "Boom <b>x</b>" : nil))
    end
    get "/admin/shiplog/sync"
    assert_select "tr.shiplog-delivery-row", 20
    assert_select "tr.shiplog-delivery-row", text: /Boom/
    assert_includes response.body, "Boom &lt;b&gt;x&lt;/b&gt;"
    assert_select "tr.shiplog-delivery-row", text: /d-0\b/, count: 0
  end

  test "warns when the webhook secret or token is missing" do
    get "/admin/shiplog/sync"
    assert_select ".shiplog-admin__flash--alert", count: 0
    Shiplog.config.webhook_secret = nil
    Shiplog.config.github_token = ""
    get "/admin/shiplog/sync"
    assert_select ".shiplog-warning", 2
  end

  test "create enqueues a sync and redirects" do
    assert_enqueued_jobs 1, only: Shiplog::SyncJob do
      post "/admin/shiplog/sync"
    end
    assert_enqueued_jobs 0, only: Shiplog::ScanChangesJob
    assert_redirected_to "/admin/shiplog/sync"
    assert flash[:notice].present?
  end

  test "create with scan=1 also enqueues the change scan" do
    assert_enqueued_jobs 1, only: Shiplog::SyncJob do
      assert_enqueued_jobs 1, only: Shiplog::ScanChangesJob do
        post "/admin/shiplog/sync", params: { scan: "1" }
      end
    end
  end

  test "forbidden when authorize_admin returns false" do
    Shiplog.config.authorize_admin = ->(_controller) { false }
    get "/admin/shiplog/sync"
    assert_response :forbidden
    assert_no_enqueued_jobs { post "/admin/shiplog/sync" }
    assert_response :forbidden
  end
end
