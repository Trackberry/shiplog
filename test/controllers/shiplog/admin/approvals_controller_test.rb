require "test_helper"

class Shiplog::Admin::ApprovalsControllerTest < ActionDispatch::IntegrationTest
  test "approve records the current admin" do
    Shiplog.config.current_admin = ->(_controller) { "boss@example.com" }
    entry = shiplog_entries(:csv_change_draft)
    post "/admin/shiplog/entries/#{entry.id}/approval"
    assert_redirected_to "/admin/shiplog/"
    entry.reload
    assert_equal "approved", entry.status
    assert_equal "boss@example.com", entry.approved_by
    assert_equal Date.current, entry.released_on
  end

  test "approving a non-draft entry redirects with an alert and changes nothing" do
    entry = shiplog_entries(:typo_change_discarded)
    post "/admin/shiplog/entries/#{entry.id}/approval"
    assert_redirected_to "/admin/shiplog/entries/#{entry.id}/edit"
    assert flash[:alert].present?
    assert_equal "discarded", entry.reload.status
  end
end
