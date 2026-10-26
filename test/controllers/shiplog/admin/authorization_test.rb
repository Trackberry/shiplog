require "test_helper"

class Shiplog::Admin::AuthorizationTest < ActionDispatch::IntegrationTest
  setup { Shiplog.config.authorize_admin = ->(_controller) { false } }

  test "every admin action is forbidden" do
    entry = shiplog_entries(:csv_change_draft)
    base = "/admin/shiplog"
    [
      [ :get, "#{base}/" ], [ :get, "#{base}/entries/#{entry.id}/edit" ], [ :patch, "#{base}/entries/#{entry.id}" ],
      [ :post, "#{base}/entries/#{entry.id}/approval" ], [ :post, "#{base}/entries/#{entry.id}/discard" ],
      [ :delete, "#{base}/entries/#{entry.id}/discard" ], [ :post, "#{base}/entries/#{entry.id}/rewrite" ],
      [ :get, "#{base}/board" ], [ :patch, "#{base}/board" ], [ :get, "#{base}/sync" ], [ :post, "#{base}/sync" ]
    ].each do |verb, path|
      public_send(verb, path)
      assert_response :forbidden, "#{verb} #{path}"
    end
    assert_equal "draft", entry.reload.status
  end
end

class Shiplog::Admin::ForgeryProtectionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @original }

  test "posts without a token are rejected" do
    entry = shiplog_entries(:csv_change_draft)
    post "/admin/shiplog/entries/#{entry.id}/approval"
    assert_response :unprocessable_content
    assert_equal "draft", entry.reload.status
  end

  test "json board updates without a token are rejected" do
    issue = shiplog_issues(:export_report)
    patch "/admin/shiplog/board", params: { column: "later", moved_id: issue.id, issue_ids: [ issue.id ] }, as: :json
    assert_response :unprocessable_content
    assert_nil issue.reload.pinned_column
  end

  test "form board updates without a token are rejected" do
    issue = shiplog_issues(:export_report)
    patch "/admin/shiplog/board", params: { issue_id: issue.id, column: "later" }
    assert_response :unprocessable_content
    assert_nil issue.reload.pinned_column
  end

  test "sync without a token is rejected" do
    assert_no_enqueued_jobs { post "/admin/shiplog/sync" }
    assert_response :unprocessable_content
  end

  test "forms include the token" do
    get "/admin/shiplog/entries/#{shiplog_entries(:csv_change_draft).id}/edit"
    assert_select "form input[name=authenticity_token]", minimum: 3
  end
end
