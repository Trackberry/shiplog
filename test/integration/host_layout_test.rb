require "test_helper"

class HostLayoutTest < ActionDispatch::IntegrationTest
  setup { Shiplog.config.public_layout = "host" }

  test "a host layout calling host route helpers renders inside the public pages" do
    get "/roadmap"
    assert_response :ok
    assert_select "#host-nav"
    assert_select "section.shiplog-column", 3

    get "/changelog"
    assert_response :ok
    assert_select "#host-nav"
  end

  test "host route helpers are forwarded to main_app" do
    get "/roadmap"
    assert_select "#host-home[href=?]", "/"
    assert_select "#host-about[href=?]", "/about"
    assert_select "#host-about-url[href=?]", "http://www.example.com/about"
  end

  test "engine helpers keep precedence" do
    get "/roadmap"
    assert_select "#engine-roadmap[href=?]", "/roadmap"
  end

  test "stylesheet and page markup are present inside the host layout" do
    get "/changelog"
    assert_select "body link[rel=stylesheet][href*='shiplog.css']", 1
    assert_select "#host-nav ~ link[rel=stylesheet]"
  end

  test "names that are not routes still raise" do
    view = ApplicationController.new.view_context
    view.extend(Shiplog::HostRoutesHelper)
    assert_raises(NoMethodError) { view.nope_path }
    assert_not view.respond_to?(:nope_path)
  end
end

class HostRoutesHelperTest < ActionView::TestCase
  include Shiplog::HostRoutesHelper

  test "forwards _path and _url names that main_app knows" do
    assert_equal "/about", about_path
    assert_respond_to self, :about_path
    assert_respond_to self, :about_url
  end

  test "does not forward other methods" do
    assert_raises(NameError) { about }
    assert_not respond_to?(:about)
  end

  test "does not forward when main_app does not know the route" do
    assert_raises(NameError) { missing_route_path }
  end

  test "passes arguments through" do
    assert_equal "/about?ref=x", about_path(ref: "x")
  end
end
