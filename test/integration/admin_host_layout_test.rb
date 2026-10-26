require "test_helper"

class AdminHostLayoutTest < ActionDispatch::IntegrationTest
  ADMIN = "/admin/shiplog".freeze
  ADMIN_CSS = "#{ADMIN}/assets/#{Shiplog::VERSION}/admin.css".freeze
  BOARD_JS = "#{ADMIN}/assets/#{Shiplog::VERSION}/board.js".freeze

  setup do
    Shiplog.config.admin_layout = "host_admin"
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @forgery_protection }

  test "admin controllers inherit from the configured parent controller" do
    assert_equal Admin::BaseController, Shiplog::Admin::ApplicationController.superclass
    get "#{ADMIN}/"
    assert_equal "1", response.headers["X-Host-Admin"]
  end

  test "admin pages render inside the host layout and reach host routes" do
    get "#{ADMIN}/"
    assert_response :ok
    assert_select "#host-admin-main .shiplog-admin"
    assert_select "#host-account[href=?]", "/account"
    assert_select "#host-admin-about[href=?]", "/about"
    assert_select "title", text: "Host admin"
  end

  test "every admin page works inside the host layout" do
    entry = shiplog_entries(:csv_change_draft)
    [ "#{ADMIN}/", "#{ADMIN}/entries/#{entry.id}/edit", "#{ADMIN}/board", "#{ADMIN}/sync" ].each do |path|
      get path
      assert_response :ok, path
      assert_select "#host-admin-header", 1, path
      assert_select "#host-admin-main .shiplog-admin", 1, path
      assert_select "link[rel=stylesheet][href=?]", ADMIN_CSS, 1, path
    end
  end

  test "the admin renders its own sub-nav inside the content area" do
    get "#{ADMIN}/"
    assert_select "#host-admin-main .shiplog-admin nav.shiplog-admin-nav--sub" do
      assert_select "a[href=?]", "#{ADMIN}/", text: "Drafts"
      assert_select "a[href=?]", "#{ADMIN}/board", text: "Roadmap board"
      assert_select "a[href=?]", "#{ADMIN}/sync", text: "Sync"
    end
  end

  test "the board includes board.js and a csrf fallback attribute" do
    get "#{ADMIN}/board"
    assert_select ".shiplog-admin script[type=module][src=?]", BOARD_JS, 1
    assert_select ".shiplog-board[data-board-url=?][data-csrf-token]", "#{ADMIN}/board"
    assert_select "meta[name=csrf-token]", 1
  end

  test "board.js reads the csrf token from the meta tag and falls back to the board element" do
    source = Rails.root.join("../../app/frontend/shiplog/board.js").read
    assert_includes source, "meta[name=csrf-token]"
    assert_includes source, "board.dataset.csrfToken"
  end

  test "forms keep working inside the host layout" do
    entry = shiplog_entries(:csv_change_draft)
    get "#{ADMIN}/entries/#{entry.id}/edit"
    assert_select ".shiplog-admin form input[name=authenticity_token]", minimum: 1

    token = css_select(".shiplog-admin form[action$='/approval'] input[name=authenticity_token]").first["value"]
    post "#{ADMIN}/entries/#{entry.id}/approval", params: { authenticity_token: token }
    assert_response :redirect
    assert_equal "approved", entry.reload.status
  end

  test "admin_layout and the page wrapper do not leak the standalone chrome" do
    get "#{ADMIN}/"
    assert_select "nav.shiplog-admin-nav:not(.shiplog-admin-nav--sub)", 0
    assert_select ".shiplog-admin--standalone", 0
    assert_select "body.shiplog-admin-body", 0
  end

  test "authorize_admin still returns 403 inside the host layout" do
    Shiplog.config.authorize_admin = ->(_controller) { false }
    get "#{ADMIN}/"
    assert_response :forbidden
    assert_select "#host-admin-header", 0
    get "#{ADMIN}/board"
    assert_response :forbidden
  end
end
