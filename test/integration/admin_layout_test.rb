require "test_helper"

class AdminLayoutTest < ActionDispatch::IntegrationTest
  test "admin layout renders nav, admin stylesheet and meta tags" do
    get "/admin/shiplog/"
    assert_response :ok
    assert_select "body main link[rel=stylesheet][href=?]", "/admin/shiplog/assets/#{Shiplog::VERSION}/admin.css", count: 1
    assert_select "head link[rel=stylesheet]", 0
    assert_select "meta[name=viewport]"
    assert_select "nav.shiplog-admin-nav a[href=?]", "/admin/shiplog/", text: "Drafts"
    assert_select "nav.shiplog-admin-nav a[href=?]", "/admin/shiplog/board", text: "Roadmap board"
    assert_select "nav.shiplog-admin-nav a[href=?]", "/admin/shiplog/sync", text: "Sync"
  end

  test "the standalone layout wraps the page in the scoped admin container" do
    get "/admin/shiplog/"
    assert_select "body.shiplog-admin-body main .shiplog-admin.shiplog-admin--standalone nav.shiplog-admin-nav"
    assert_select ".shiplog-admin nav.shiplog-admin-nav--sub", 0
  end

  test "the standalone layout shows flash messages" do
    entry = shiplog_entries(:csv_change_draft)
    post "/admin/shiplog/entries/#{entry.id}/approval"
    follow_redirect!
    assert_select ".shiplog-admin .shiplog-admin__flash--notice[role=status]"
  end

  test "the board script loads once, from the page" do
    get "/admin/shiplog/board"
    assert_select "script[type=module][src=?]", "/admin/shiplog/assets/#{Shiplog::VERSION}/board.js", count: 1
    assert_select ".shiplog-board[data-csrf-token]"
  end
end
