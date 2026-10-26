require "test_helper"

class AdminLayoutTest < ActionDispatch::IntegrationTest
  test "admin layout renders nav, admin stylesheet and meta tags" do
    get "/admin/shiplog/"
    assert_response :ok
    assert_select "link[rel=stylesheet][href=?]", "/admin/shiplog/assets/#{Shiplog::VERSION}/admin.css"
    assert_select "meta[name=viewport]"
    assert_select "nav.shiplog-admin-nav a[href=?]", "/admin/shiplog/", text: "Drafts"
    assert_select "nav.shiplog-admin-nav a[href=?]", "/admin/shiplog/board", text: "Roadmap board"
    assert_select "nav.shiplog-admin-nav a[href=?]", "/admin/shiplog/sync", text: "Sync"
  end
end
