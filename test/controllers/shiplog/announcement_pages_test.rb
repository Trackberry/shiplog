require "test_helper"
require "rexml/document"

class Shiplog::AnnouncementPagesTest < ActionDispatch::IntegrationTest
  ATOM = "http://www.w3.org/2005/Atom".freeze
  BODY = "Intro with a [link](/changelog/dark-mode).\n\n## Highlights\n\n### Dark mode\n\nTry it.\n\n- one\n- two".freeze

  setup do
    @announcement = Shiplog::Announcements.draft(month: Date.new(2026, 10, 1))
    @announcement.update!(title: "October recap", body: BODY)
  end

  def publish!
    @announcement.approve!(by: "ed@example.com")
  end

  def feed = REXML::Document.new(response.body)

  def feed_titles = REXML::XPath.match(feed, "/a:feed/a:entry/a:title", "a" => ATOM).map(&:text)

  def month_link(path: "/changelog/2026-10")
    css_select("section[aria-labelledby=shiplog-month-2026-10] a").select { |link| link["href"] == path }
  end

  # The engine marks a page it does not serve with X-Cascade: pass (the host router strips it from the final response).
  def cascades?(path)
    status, headers, = Shiplog::Engine.call(Rack::MockRequest.env_for(path))
    status == 404 && headers.find { |name, _| name.casecmp?("x-cascade") }&.last == "pass"
  end

  test "an approved announcement renders its title and its Markdown as HTML" do
    publish!

    get "/changelog/2026-10"

    assert_response :ok
    assert_select "article.shiplog-announcement" do
      assert_select "h2.shiplog-announcement__title", text: "October recap"
      assert_select "time[datetime=?]", "2026-10", text: "October 2026"
      assert_select ".shiplog-announcement__body" do
        assert_select "h3", text: "Highlights"
        assert_select "h4", text: "Dark mode"
        assert_select "h2", count: 0
        assert_select "a[href=?]", "/changelog/dark-mode", text: "link"
        assert_select "ul li", 2
      end
    end
    assert_select "title", text: "October recap · Changelog"
    assert_select "a[href=?]", "/changelog#shiplog-month-2026-10"
  end

  test "raw HTML in the body is escaped, never rendered" do
    @announcement.update!(body: "<script>alert(1)</script>\n\n<img src=x onerror=alert(2)> and [bad](javascript:alert(3))")
    publish!

    get "/changelog/2026-10"

    assert_response :ok
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_not_includes response.body, "<img src=x"
    assert_not_includes response.body, 'href="javascript:'
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "the meta description is plain text" do
    publish!

    get "/changelog/2026-10"

    description = css_select("meta[name=description]").first["content"]
    assert_includes description, "Intro with a link (/changelog/dark-mode)."
    assert_not_includes description, "##"
    assert_not_includes description, "]("
    assert_not_includes description, "["
    assert_select "meta[property='og:title'][content=?]", "October recap"
    assert_select "meta[property='og:url'][content=?]", "http://www.example.com/changelog/2026-10"
  end

  test "revalidating with the ETag answers 304, and an edit changes it" do
    publish!

    get "/changelog/2026-10"
    etag = response.headers["ETag"]
    get "/changelog/2026-10", headers: { "If-None-Match" => etag }
    assert_response :not_modified

    travel 1.minute
    @announcement.update!(body: "Changed text")
    get "/changelog/2026-10", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_not_equal etag, response.headers["ETag"]
  end

  test "a draft announcement is not found and lets the host's routes try" do
    get "/changelog/2026-10"

    assert_response :not_found
    assert cascades?("/changelog/2026-10")
  end

  test "a discarded announcement is not found" do
    @announcement.discard!(reason: "no")

    get "/changelog/2026-10"

    assert_response :not_found
  end

  test "an unknown month is not found" do
    publish!

    get "/changelog/2026-11"

    assert_response :not_found
    assert cascades?("/changelog/2026-11")
  end

  test "with announcements published externally or off, there is no page" do
    publish!

    [ :external, false ].each do |mode|
      Shiplog.config.announcements = mode
      get "/changelog/2026-10"

      assert_response :not_found, mode.inspect
      assert cascades?("/changelog/2026-10"), mode.inspect
    end
  end

  test "features and changes keep their pages" do
    publish!

    get "/changelog/dark-mode"

    assert_response :ok
    assert_select "article.shiplog-permalink"
  end

  test "on_changelog_seen is called, and the controller's entry is the announcement" do
    publish!
    seen = []
    Shiplog.config.on_changelog_seen = ->(controller) { seen << controller.shiplog_entry }

    get "/changelog/2026-10"

    assert_equal [ @announcement ], seen
    assert seen.first.announcement?
  end

  test "the changelog list links the month's summary under the month heading once it is approved" do
    get "/changelog"
    assert_select "a", text: "Read the October 2026 summary", count: 0

    publish!
    get "/changelog"

    assert_response :ok
    assert_equal 1, month_link.size
    assert_equal "Read the October 2026 summary", month_link.first.text.strip
    assert_select "section[aria-labelledby=shiplog-month-2026-10] h2 + p a", text: "Read the October 2026 summary"
  end

  test "the list shows no summary link for a month without an approved announcement" do
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 9, 15))
    publish!

    get "/changelog"

    assert_select "section[aria-labelledby=shiplog-month-2026-09] a", text: /summary/, count: 0
    assert_equal 1, month_link.size
  end

  test "an announcement is not listed as an entry" do
    publish!

    get "/changelog"

    assert_equal [ "Dark mode" ], css_select(".shiplog-entry__title").map(&:text)
  end

  test "the list's ETag changes when the announcement is approved" do
    get "/changelog"
    etag = response.headers["ETag"]

    publish!
    get "/changelog", headers: { "If-None-Match" => etag }

    assert_response :ok
  end

  test "with announcements published externally the link uses config.announcement_url" do
    publish!
    Shiplog.config.announcements = :external
    Shiplog.config.announcement_url = ->(announcement, locale) { "https://blog.example.com/#{announcement.slug}?l=#{locale}" }

    get "/changelog"

    assert_equal 1, month_link(path: "https://blog.example.com/2026-10?l=en").size
  end

  test "an external announcement_url can use the host's route helpers" do
    publish!
    Shiplog.config.announcements = :external
    Shiplog.config.announcement_url = ->(_announcement, _locale) { main_app.about_path }

    get "/changelog"

    assert_equal 1, month_link(path: "/about").size
  end

  test "an unsafe, blank or failing announcement_url renders no link and the page still works" do
    publish!
    Shiplog.config.announcements = :external

    [ ->(*) { "javascript:alert(1)" }, ->(*) { "//evil.example.com" }, ->(*) { nil }, ->(*) { 42 }, ->(*) { raise "boom" } ].each do |callable|
      Shiplog.config.announcement_url = callable
      get "/changelog"

      assert_response :ok
      assert_select "section[aria-labelledby=shiplog-month-2026-10] a", text: /summary/, count: 0
      assert_select "a[href^=javascript]", count: 0
    end
  end

  test "external announcements without announcement_url render no link" do
    publish!
    Shiplog.config.announcements = :external

    get "/changelog"

    assert_response :ok
    assert_select "a", text: /summary/, count: 0
  end

  test "with announcements off there is no link" do
    publish!
    Shiplog.config.announcements = false
    Shiplog.config.announcement_url = ->(*) { "https://blog.example.com/x" }

    get "/changelog"

    assert_response :ok
    assert_select "a", text: /summary/, count: 0
    assert_select "a[href=?]", "https://blog.example.com/x", count: 0
  end

  test "the Atom feed includes the announcement with its Markdown rendered as HTML" do
    publish!

    get "/changelog.atom"

    assert_response :ok
    assert_includes feed_titles, "October recap"
    assert_includes feed_titles, "Dark mode"
    entry = REXML::XPath.match(feed, "/a:feed/a:entry", "a" => ATOM).find { |node| REXML::XPath.first(node, "a:title", "a" => ATOM).text == "October recap" }
    assert_equal "http://www.example.com/changelog/2026-10", REXML::XPath.first(entry, "a:link", "a" => ATOM).attributes["href"]
    assert_equal "tag:www.example.com,2005:/changelog/2026-10", REXML::XPath.first(entry, "a:id", "a" => ATOM).text
    content = REXML::XPath.first(entry, "a:content", "a" => ATOM)
    assert_equal "html", content.attributes["type"]
    assert_includes content.text, "<h2>Highlights</h2>"
    assert_includes content.text, %(<a href="/changelog/dark-mode">link</a>)
    assert_not_includes content.text, "##"
  end

  test "the feed leaves a draft announcement out" do
    get "/changelog.atom"

    assert_equal [ "Dark mode" ], feed_titles
  end

  test "an area-filtered feed has no announcements" do
    publish!
    area = Shiplog::Area.create!(name: "Billing")
    shiplog_entries(:dark_mode_feature).update!(area:)

    get "/changelog.atom", params: { area: area.slug }

    assert_response :ok
    assert_equal [ "Dark mode" ], feed_titles
  end

  test "the feed has no announcements when they are published externally or off" do
    publish!

    [ :external, false ].each do |mode|
      Shiplog.config.announcements = mode
      get "/changelog.atom"

      assert_response :ok
      assert_equal [ "Dark mode" ], feed_titles, mode.inspect
    end
  end

  test "search results never include announcements" do
    publish!
    @announcement.update!(title: "Dark mode recap", body: "Dark mode and more dark things")

    get "/changelog", params: { q: "dark" }

    assert_response :ok
    assert_equal [ "Dark mode" ], css_select(".shiplog-entry__title").map(&:text)
    assert_select ".shiplog-entry__title a[href=?]", "/changelog/2026-10", count: 0
  end

  test "the Spanish translation is shown under the es locale" do
    Shiplog.config.locales = [ :es ]
    publish!
    @announcement.translations.create!(locale: "es", title: "Resumen de octubre", body: "## Destacados\n\nTexto en español.",
      source_digest: @announcement.translation_source_digest)

    I18n.with_locale(:es) { get "/changelog/2026-10" }

    assert_response :ok
    assert_select "h2.shiplog-announcement__title", text: "Resumen de octubre"
    assert_select ".shiplog-announcement__body h3", text: "Destacados"
    assert_select ".shiplog-announcement__body", text: /Texto en español/
    assert_select "title", text: /Resumen de octubre/

    get "/changelog/2026-10"
    assert_select "h2.shiplog-announcement__title", text: "October recap"
  end

  test "the Spanish list links to the summary with the Spanish text" do
    Shiplog.config.locales = [ :es ]
    publish!

    I18n.with_locale(:es) { get "/changelog" }

    assert_equal 1, month_link.size
    assert_match(/\ALeer el resumen de /, month_link.first.text.strip)
  end

  test "a stale translation falls back to English on the page" do
    Shiplog.config.locales = [ :es ]
    publish!
    @announcement.translations.create!(locale: "es", title: "Resumen de octubre", body: "Texto", source_digest: "stale")

    I18n.with_locale(:es) { get "/changelog/2026-10" }

    assert_select "h2.shiplog-announcement__title", text: "October recap"
  end
end
