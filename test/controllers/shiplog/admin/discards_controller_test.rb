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
end
