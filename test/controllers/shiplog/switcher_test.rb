require "test_helper"

class Shiplog::SwitcherTest < ActionDispatch::IntegrationTest
  test "the default header links the roadmap and the changelog, marking the current page" do
    get "/roadmap"
    assert_select "header.shiplog-page__header nav.shiplog-switcher[aria-label=?]", "Product updates" do
      assert_select "a.shiplog-switcher__link", 2
      assert_select "a.shiplog-switcher__link[href=?][aria-current=page]", "/roadmap", text: "Roadmap"
      assert_select "a.shiplog-switcher__link.shiplog-switcher__link--current", 1
      assert_select "a.shiplog-switcher__link[href=?]:not([aria-current])", "/changelog", text: "Changelog"
    end

    get "/changelog"
    assert_select "a.shiplog-switcher__link[href=?][aria-current=page]", "/changelog", text: "Changelog"
    assert_select "a.shiplog-switcher__link[href=?]:not([aria-current])", "/roadmap"
  end

  test "extra pages with String labels and paths follow the two defaults" do
    Shiplog.config.extra_pages = [ { label: "News", path: "/news" } ]
    get "/roadmap"

    assert_select "nav.shiplog-switcher a.shiplog-switcher__link", 3
    assert_select "nav.shiplog-switcher a.shiplog-switcher__link:nth-of-type(3)[href=?]", "/news", text: "News"
    assert_select "nav.shiplog-switcher [aria-current]", 1
  end

  test "extra pages accept callables evaluated in the view" do
    Shiplog.config.extra_pages = [ { label: -> { t("shiplog.roadmap.title").upcase }, path: -> { main_app.news_path } } ]
    get "/changelog"

    assert_select "nav.shiplog-switcher a[href=?]", "/news", text: "ROADMAP"
  end

  test "an extra page is current when the request path starts with its path" do
    Shiplog.config.extra_pages = [ { label: "Mount", path: "/roadmap/archive" } ]
    get "/roadmap"
    assert_select "nav.shiplog-switcher [aria-current=page]", text: "Roadmap", count: 1
    assert_select "nav.shiplog-switcher a[href=?]:not([aria-current])", "/roadmap/archive"
  end

  test "the switcher renders on a host page through shiplog_switcher, with the extra page current" do
    Shiplog.config.extra_pages = [ { label: "News", path: -> { main_app.news_path } } ]
    get "/news"

    assert_response :ok
    assert_select "#host-news nav.shiplog-switcher[aria-label=?]", "Product updates" do
      assert_select "a.shiplog-switcher__link[href=?]:not([aria-current])", "/roadmap", text: "Roadmap"
      assert_select "a.shiplog-switcher__link[href=?]:not([aria-current])", "/changelog", text: "Changelog"
      assert_select "a.shiplog-switcher__link[href=?][aria-current=page]", "/news", text: "News"
    end
    assert_select "link[rel=stylesheet][href*='shiplog.css']", 1
  end

  test "shiplog_switcher leaves out the bundled stylesheet when it is off" do
    Shiplog.config.stylesheet = false
    get "/news"
    assert_select "link[rel=stylesheet][href*='shiplog.css']", 0
    assert_select "nav.shiplog-switcher"
  end

  test "configured classes apply to the switcher and its links, current included" do
    Shiplog.config.classes = { switcher: "inline-flex rounded-full", switcher_link: "px-4 py-1" }
    get "/roadmap"

    assert_select "nav.shiplog-switcher.inline-flex.rounded-full"
    assert_select "a.shiplog-switcher__link.px-4.py-1", 2
    assert_select "a.shiplog-switcher__link--current.px-4", 1
  end

  test "labels and the nav label come from I18n" do
    I18n.backend.store_translations(:en, shiplog: { switcher: { label: "Updates", roadmap: "Plans" } })
    get "/roadmap"
    assert_select "nav.shiplog-switcher[aria-label=?]", "Updates"
    assert_select "nav.shiplog-switcher a", text: "Plans"
  ensure
    I18n.backend.reload!
  end

  test "only the longest matching path is current" do
    Shiplog.config.extra_pages = [ { label: "News", path: "/news" }, { label: "Archive", path: "/news/archive" } ]
    get "/news/archive"
    assert_select "nav.shiplog-switcher [aria-current=page]", 1
    assert_select "nav.shiplog-switcher a[href=?][aria-current=page]", "/news/archive"
    get "/news"
    assert_select "nav.shiplog-switcher a[href=?][aria-current=page]", "/news"
  end

  test "an extra page given as an absolute URL is current by its path" do
    Shiplog.config.extra_pages = [ { label: "News", path: -> { "http://www.example.com#{main_app.news_path}" } } ]
    get "/news"
    assert_select "nav.shiplog-switcher a[href=?][aria-current=page]", "http://www.example.com/news"
  end

  test "a callable path with an unsafe scheme renders as plain text and logs once" do
    Shiplog.config.extra_pages = [ { label: "Bad", path: -> { "javascript:alert(1)" } } ]
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    Shiplog::SwitcherHelper.reset_warnings!
    2.times { get "/roadmap" }
    assert_select "nav.shiplog-switcher a", 2
    assert_select "nav.shiplog-switcher a[href^=javascript]", 0
    assert_select "nav.shiplog-switcher", text: /Bad/
    assert_equal 1, io.string.scan("javascript:").size
  ensure
    Rails.logger = original
  end

  test "shiplog_switcher emits the stylesheet once per page" do
    get "/news", params: { twice: 1 }
    assert_select "nav.shiplog-switcher", 2
    assert_select "link[rel=stylesheet][href*='shiplog.css']", 1
  end
end
