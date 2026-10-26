require "test_helper"

class Shiplog::Admin::InlineInboxTest < ActionDispatch::IntegrationTest
  ADMIN = "/admin/shiplog".freeze
  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  test "approve responds with the re-rendered row, the filter match and the message" do
    entry = shiplog_entries(:csv_change_draft)
    post "#{ADMIN}/entries/#{entry.id}/approval?status=draft", headers: JSON_HEADERS
    assert_response :ok
    body = response.parsed_body
    assert_equal false, body["matches_filter"]
    assert_equal I18n.t("shiplog.admin.entries.approved"), body["message"]
    row = Nokogiri::HTML::DocumentFragment.parse(body["row"])
    assert_equal 1, row.css("tr#shiplog-entry-#{entry.id}.shiplog-entry-row").size
    assert_equal "approved", entry.reload.status
  end

  test "approve keeps the row when the filter is the approved list" do
    entry = shiplog_entries(:csv_change_draft)
    post "#{ADMIN}/entries/#{entry.id}/approval?status=approved&kind=change", headers: JSON_HEADERS
    assert_equal true, response.parsed_body["matches_filter"]
  end

  test "the kind filter decides the match" do
    entry = shiplog_entries(:csv_change_draft)
    post "#{ADMIN}/entries/#{entry.id}/approval?status=approved&kind=feature", headers: JSON_HEADERS
    assert_equal false, response.parsed_body["matches_filter"]
  end

  test "the default filter is drafts" do
    entry = shiplog_entries(:csv_change_draft)
    post "#{ADMIN}/entries/#{entry.id}/discard", params: { reason: "x" }, headers: JSON_HEADERS
    assert_equal false, response.parsed_body["matches_filter"]
    assert_equal I18n.t("shiplog.admin.entries.discarded"), response.parsed_body["message"]
  end

  test "restore responds with the row and matches the discarded list only when it stays there" do
    entry = shiplog_entries(:typo_change_discarded)
    delete "#{ADMIN}/entries/#{entry.id}/discard?status=discarded", headers: JSON_HEADERS
    assert_response :ok
    assert_equal false, response.parsed_body["matches_filter"]
    assert_equal I18n.t("shiplog.admin.entries.restored"), response.parsed_body["message"]
    assert_equal "draft", entry.reload.status
  end

  test "the rendered row carries the filters and the inline marker" do
    entry = shiplog_entries(:csv_change_draft)
    post "#{ADMIN}/entries/#{entry.id}/approval?status=draft&kind=change", headers: JSON_HEADERS
    row = Nokogiri::HTML::DocumentFragment.parse(response.parsed_body["row"])
    assert row.css("a[href*='kind=change']").any?
  end

  test "an invalid transition responds 422 with an error and changes nothing" do
    entry = shiplog_entries(:typo_change_discarded)
    post "#{ADMIN}/entries/#{entry.id}/approval", headers: JSON_HEADERS
    assert_response :unprocessable_content
    assert_equal I18n.t("shiplog.admin.entries.invalid_transition"), response.parsed_body["error"]
    assert_equal "discarded", entry.reload.status
  end

  test "restoring a non-discarded entry responds 422" do
    entry = shiplog_entries(:dark_mode_feature)
    delete "#{ADMIN}/entries/#{entry.id}/discard", headers: JSON_HEADERS
    assert_response :unprocessable_content
    assert response.parsed_body["error"].present?
  end

  test "html requests keep redirecting" do
    entry = shiplog_entries(:csv_change_draft)
    post "#{ADMIN}/entries/#{entry.id}/approval?status=draft"
    assert_redirected_to "#{ADMIN}/?status=draft"
  end

  test "the index loads the inbox script and marks the row forms inline" do
    get "#{ADMIN}/"
    assert_select "script[type=module][src=?]", "/admin/shiplog/assets/#{Shiplog::VERSION}/inbox.js"
    assert_select "[data-shiplog-inbox] form[data-shiplog-inline] button", minimum: 1
    assert_select "[data-shiplog-inbox] [role=status][aria-live=polite]"
  end

  test "serves the inbox module as javascript" do
    get "/admin/shiplog/assets/#{Shiplog::VERSION}/inbox.js"
    assert_response :ok
    assert_equal "text/javascript", response.media_type
  end
end
