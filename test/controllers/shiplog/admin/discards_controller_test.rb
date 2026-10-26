require "test_helper"

class Shiplog::Admin::DiscardsControllerTest < ActionDispatch::IntegrationTest
  test "discard stores the reason" do
    entry = shiplog_entries(:csv_change_draft)
    post "/admin/shiplog/entries/#{entry.id}/discard", params: { reason: "Internal only" }
    assert_redirected_to "/admin/shiplog/"
    assert_equal [ "discarded", "Internal only" ], [ entry.reload.status, entry.discard_reason ]
  end

  test "restore brings the entry back to draft" do
    entry = shiplog_entries(:typo_change_discarded)
    delete "/admin/shiplog/entries/#{entry.id}/discard"
    assert_redirected_to "/admin/shiplog/"
    assert_equal [ "draft", nil ], [ entry.reload.status, entry.discard_reason ]
  end

  test "discarding a non-draft entry redirects with an alert and changes nothing" do
    entry = shiplog_entries(:dark_mode_feature)
    post "/admin/shiplog/entries/#{entry.id}/discard", params: { reason: "late" }
    assert_redirected_to "/admin/shiplog/entries/#{entry.id}/edit"
    assert flash[:alert].present?
    assert_equal [ "approved", nil ], [ entry.reload.status, entry.discard_reason ]
  end

  test "restoring a non-discarded entry redirects with an alert" do
    entry = shiplog_entries(:dark_mode_feature)
    delete "/admin/shiplog/entries/#{entry.id}/discard"
    assert_redirected_to "/admin/shiplog/entries/#{entry.id}/edit"
    assert flash[:alert].present?
    assert_equal "approved", entry.reload.status
  end
end
