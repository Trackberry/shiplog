require "test_helper"

class Shiplog::ChangelogEntriesControllerTest < ActionDispatch::IntegrationTest
  def publish(title, released_on, approved_at: Time.current, body: "Body")
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: title,
      committed_at: Time.current, url: "https://github.com/x/y/commit/1")
    Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title:, body:, released_on:, approved_at:)
      .tap(&:ensure_slug!)
  end

  test "an approved feature has a page at /changelog/:slug" do
    get "/changelog/dark-mode"
    assert_response :ok
    assert_select "article.shiplog-permalink" do
      assert_select ".shiplog-entry__category", text: "New"
      assert_select "time.shiplog-entry__date[datetime=?]", "2026-10-09", text: "9 October 2026"
      assert_select ".shiplog-entry__title", text: "Dark mode"
      assert_select ".shiplog-entry__body", text: /Switch to a dark theme/
    end
    assert_select "nav.shiplog-switcher a[aria-current=page]", text: "Changelog"
  end

  test "the page title is set" do
    get "/changelog/dark-mode"
    assert_select "title", text: "Dark mode · Changelog"
  end

  test "description and Open Graph tags are rendered" do
    get "/changelog/dark-mode"
    assert_select "meta[name=description][content=?]", "Switch to a dark theme."
    assert_select "meta[property='og:title'][content=?]", "Dark mode"
    assert_select "meta[property='og:description'][content=?]", "Switch to a dark theme."
    assert_select "meta[property='og:type'][content=?]", "article"
    assert_select "meta[property='og:url'][content=?]", "http://www.example.com/changelog/dark-mode"
    assert_select "meta[property='og:image']", 0
  end

  test "a long body is truncated in the description" do
    publish("Long one", Date.new(2026, 9, 1), body: "word " * 100)
    get "/changelog/long-one"
    assert_operator css_select("meta[name=description]").first["content"].length, :<=, 200
  end

  test "drafts, discarded and roadmap entries and unknown slugs are 404" do
    shiplog_entries(:csv_change_draft).update_columns(slug: "better-csv")
    shiplog_entries(:typo_change_discarded).update_columns(slug: "typo-fix")
    shiplog_entries(:bulk_upload_roadmap).update_columns(slug: "upload-many")

    %w[better-csv typo-fix upload-many nope].each do |slug|
      get "/changelog/#{slug}"
      assert_response :not_found, slug
    end
  end

  test "an entry unpublished after the fact is a 404" do
    shiplog_entries(:dark_mode_feature).update_columns(status: "discarded")
    get "/changelog/dark-mode"
    assert_response :not_found
  end

  test "newer and older neighbours are linked" do
    publish("Older thing", Date.new(2026, 9, 1))
    publish("Newer thing", Date.new(2026, 10, 20))
    get "/changelog/dark-mode"

    assert_select "nav.shiplog-permalink__nav" do
      assert_select "a.shiplog-permalink__nav-link[rel=prev][href=?]", "/changelog/newer-thing", text: /Newer thing/
      assert_select "a.shiplog-permalink__nav-link[rel=next][href=?]", "/changelog/older-thing", text: /Older thing/
    end
  end

  test "the nav only lists neighbours that exist" do
    get "/changelog/dark-mode"
    assert_select "nav.shiplog-permalink__nav", 0
  end

  test "the back link goes to the month anchor on the changelog" do
    get "/changelog/dark-mode"
    assert_select "a.shiplog-permalink__back[href=?]", "/changelog#shiplog-month-2026-10", text: /Back to the changelog/
  end

  test "the changelog list links each title to its permalink" do
    get "/changelog"
    assert_select "h3.shiplog-entry__title a[href=?]", "/changelog/dark-mode", text: "Dark mode"
  end

  test "approved entries without a slug get one when the list renders" do
    shiplog_entries(:dark_mode_feature).update_columns(slug: nil)
    get "/changelog"
    assert_select "h3.shiplog-entry__title a[href=?]", "/changelog/dark-mode"
    assert_equal "dark-mode", shiplog_entries(:dark_mode_feature).reload.slug
  end

  test "the ETag is stable, answers 304, and changes with the entry or a neighbour" do
    neighbour = publish("Older thing", Date.new(2026, 9, 1))
    get "/changelog/dark-mode"
    etag = response.headers["ETag"]
    assert etag

    get "/changelog/dark-mode", headers: { "If-None-Match" => etag }
    assert_response :not_modified

    travel 1.minute do
      neighbour.update!(title: "Older thing, renamed")
    end
    get "/changelog/dark-mode", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_not_equal etag, response.headers["ETag"]
    assert_select "a.shiplog-permalink__nav-link", text: /renamed/
  end

  test "a new neighbour changes the ETag" do
    get "/changelog/dark-mode"
    etag = response.headers["ETag"]
    publish("Newer thing", Date.new(2026, 10, 20))
    get "/changelog/dark-mode", headers: { "If-None-Match" => etag }
    assert_response :ok
  end

  test "the discovery link points at the feed" do
    get "/changelog/dark-mode"
    assert_select "link[rel=alternate][type='application/atom+xml'][href=?]", "http://www.example.com/changelog.atom"
  end

  test "the entry title is not interpreted as HTML" do
    shiplog_entries(:dark_mode_feature).update_columns(title: "<script>x</script> mode")
    get "/changelog/dark-mode"
    assert_no_match(/<script>x/, response.body)
  end

  test "pages render without translation-missing text under another locale" do
    with_extra_locale(:fr) do
      I18n.backend.store_translations(:fr, date: { month_names: [ nil ] + %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre] })
      publish("Older thing", Date.new(2026, 9, 1))
      get "/changelog/dark-mode"
      assert_response :ok
      assert_no_match(/translation[ _]missing/i, response.body)
      assert_select "a.shiplog-permalink__back", text: /Back to the changelog/
    end
  end

  test "the config.classes extras are applied to the permalink elements" do
    Shiplog.config.classes = { permalink: "x-permalink", permalink_back: "x-back", permalink_nav: "x-nav", permalink_nav_link: "x-nav-link" }
    publish("Older thing", Date.new(2026, 9, 1))
    get "/changelog/dark-mode"
    assert_select "article.shiplog-permalink.x-permalink"
    assert_select "a.shiplog-permalink__back.x-back"
    assert_select "nav.shiplog-permalink__nav.x-nav"
    assert_select "a.shiplog-permalink__nav-link.x-nav-link"
  end

  test "routing: slugs never swallow the feed and the feed never swallows slugs" do
    routes = Shiplog::Engine.routes
    assert_equal({ controller: "shiplog/changelog_entries", action: "show", slug: "dark-mode" }, routes.recognize_path("/changelog/dark-mode"))
    assert_equal({ controller: "shiplog/changelog_feeds", action: "show", format: "atom" }, routes.recognize_path("/changelog.atom"))
    assert_equal({ controller: "shiplog/changelogs", action: "show" }, routes.recognize_path("/changelog"))
    assert_raises(ActionController::RoutingError) { routes.recognize_path("/changelog/dark-mode.atom") }
  end

  test "a request for /changelog.atom is the feed, and /changelog/<slug>.atom is a 404" do
    get "/changelog.atom"
    assert_equal "application/atom+xml", response.media_type
    get "/changelog/dark-mode.atom"
    assert_response :not_found
  end

  test "on_changelog_seen is called with the controller on a 200" do
    seen = []
    Shiplog.config.on_changelog_seen = ->(controller) { seen << controller }
    get "/changelog/dark-mode"
    assert_equal 1, seen.size
    assert_kind_of Shiplog::ChangelogEntriesController, seen.first
  end

  test "on_changelog_seen is called on a 304 (a revisit is a visit) but not on a 404" do
    seen = []
    Shiplog.config.on_changelog_seen = ->(controller) { seen << controller.response.status }
    get "/changelog/dark-mode"
    etag = response.headers["ETag"]
    get "/changelog/dark-mode", headers: { "If-None-Match" => etag }
    assert_response :not_modified
    get "/changelog/nope"
    assert_equal [ 200, 304 ], seen
  end
end
