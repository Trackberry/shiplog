require "test_helper"

class Shiplog::ChangelogsControllerTest < ActionDispatch::IntegrationTest
  def create_entries(count, kind: "change", released_on: Date.new(2026, 9, 1), offset: 10_000)
    now = Time.current
    rows = Array.new(count) do |i|
      { kind:, status: "approved", subject_type: "Shiplog::Issue", subject_id: offset + i,
        title: "Bulk #{kind} #{offset + i}", body: "Body", released_on:, created_at: now, updated_at: now }
    end
    Shiplog::Entry.insert_all!(rows)
  end

  test "lists approved features grouped by month heading" do
    shiplog_entries(:csv_change_draft).approve!(by: "ed@example.com")
    shiplog_entries(:csv_change_draft).update!(released_on: Date.new(2026, 9, 15))
    get "/changelog"
    assert_response :ok
    assert_select "h2.shiplog-month__title", text: "October 2026"
    assert_select "h2.shiplog-month__title", text: "September 2026"
    assert_select ".shiplog-entry__title", text: "Dark mode"
    assert_select ".shiplog-entry__title", text: "Better CSV validation"
  end

  test "months are newest first" do
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 9, 15))
    get "/changelog"
    titles = css_select("h2.shiplog-month__title").map(&:text)
    assert_equal [ "October 2026", "September 2026" ], titles
  end

  test "excludes drafts, discarded and roadmap entries" do
    get "/changelog"
    assert_not_includes response.body, "Better CSV validation"
    assert_not_includes response.body, "Typo fix"
    assert_not_includes response.body, "Upload many shipments at once"
  end

  test "entries show the category pill, the date, the title and the body" do
    get "/changelog"
    assert_select "li.shiplog-entry" do
      assert_select ".shiplog-entry__category", text: "New"
      assert_select "time.shiplog-entry__date[datetime=?]", shiplog_entries(:dark_mode_feature).released_on.iso8601
      assert_select "h3.shiplog-entry__title", text: "Dark mode"
      assert_select ".shiplog-entry__body"
    end
    assert_select "time.shiplog-entry__date", text: I18n.l(shiplog_entries(:dark_mode_feature).released_on, format: I18n.t("shiplog.date_format"))
  end

  test "change entries are labelled Improved" do
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 10, 1))
    get "/changelog"
    assert_select "li.shiplog-entry--change .shiplog-entry__category", text: "Improved"
  end

  test "months are labelled sections" do
    get "/changelog"
    assert_select "section.shiplog-month[aria-labelledby=shiplog-month-2026-10] h2#shiplog-month-2026-10.shiplog-month__title"
  end

  test "configured classes are added, feature classes only on feature entries" do
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 10, 1))
    Shiplog.config.classes = { entry: "rounded", entry_feature: "border-l-4", entry_category: "pill", pagination_link: "link" }
    get "/changelog"
    assert_select "li.shiplog-entry.shiplog-entry--feature.rounded.border-l-4", 1
    assert_select "li.shiplog-entry--change.rounded", 1
    assert_select "li.shiplog-entry--change.border-l-4", 0
    assert_select ".shiplog-entry__category.pill", 2
  end

  test "has a page header and the stylesheet inside the page" do
    get "/changelog"
    assert_select "header.shiplog-page__header h1.shiplog-page__title", text: "Changelog"
    assert_select "main .shiplog-page.shiplog-page--changelog"
    assert_select "body link[rel=stylesheet][href*='shiplog.css']", 1
  end

  test "stylesheet false leaves out the bundled stylesheet" do
    Shiplog.config.stylesheet = false
    get "/changelog"
    assert_select "link[rel=stylesheet]", 0
  end

  test "feature entries are marked" do
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 10, 1))
    get "/changelog"
    assert_select "li.shiplog-entry--feature", 1
    assert_select "li.shiplog-entry--feature .shiplog-entry__title", text: "Dark mode"
    assert_select "li.shiplog-entry--change", 1
  end

  test "escapes HTML in bodies" do
    shiplog_entries(:dark_mode_feature).update!(body: "<b>bold</b>")
    get "/changelog"
    assert_not_includes response.body, "<b>bold</b>"
    assert_includes response.body, "&lt;b&gt;bold&lt;/b&gt;"
  end

  test "never leaks GitHub details" do
    get "/changelog"
    assert_not_includes response.body, "github.com"
  end

  test "empty state" do
    Shiplog::Entry.update_all(status: "draft")
    get "/changelog"
    assert_select "p.shiplog-empty", text: "Nothing here yet"
  end

  test "ETag changes after approving an entry" do
    get "/changelog"
    etag = response.headers["ETag"]
    entry = shiplog_entries(:csv_change_draft)
    entry.update!(released_on: Date.new(2026, 10, 11))
    entry.approve!(by: "ed@example.com")
    get "/changelog", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes when config.classes changes" do
    get "/changelog"
    etag = response.headers["ETag"]
    Shiplog.config.classes = { card: "rounded" }
    get "/changelog"
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes when config.stylesheet changes" do
    get "/changelog"
    etag = response.headers["ETag"]
    Shiplog.config.stylesheet = false
    get "/changelog"
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes with the gem version" do
    get "/changelog"
    etag = response.headers["ETag"]
    original = Shiplog::VERSION
    begin
      silence_warnings { Shiplog.const_set(:VERSION, "9.9.9") }
      get "/changelog"
      assert_not_equal etag, response.headers["ETag"]
    ensure
      silence_warnings { Shiplog.const_set(:VERSION, original) }
    end
  end

  test "the entry date uses the engine's own date format, not date.formats.long" do
    shiplog_entries(:dark_mode_feature).update!(released_on: Date.new(2026, 10, 5))
    get "/changelog"
    assert_select "time.shiplog-entry__date", text: "5 October 2026"
  end

  test "a host locale without date.formats.long still renders the changelog" do
    with_extra_locale(:fr) do
      I18n.backend.store_translations(:fr, shiplog: { date_format: "%d/%m/%Y" })
      get "/changelog"
      assert_response :ok
      assert_select "time.shiplog-entry__date", text: /\d\d\/\d\d\/2026/
    end
  end

  test "a host locale without any shiplog translations falls back to the default date format" do
    with_extra_locale(:fr) do
      get "/changelog"
      assert_response :ok
    end
  end

  test "with_extra_locale restores the I18n backend" do
    with_extra_locale(:fr) { I18n.backend.store_translations(:fr, shiplog: { date_format: "%d" }) }
    assert_not_includes I18n.available_locales, :fr
    with_extra_locale(:fr) { assert_equal "unset", I18n.t("shiplog.date_format", default: "unset") }
    assert_equal "%-d %B %Y", I18n.t("shiplog.date_format")
  end

  test "ETag differs per locale" do
    get "/changelog"
    english = response.headers["ETag"]
    with_extra_locale(:fr) { get "/changelog" }
    assert_not_equal english, response.headers["ETag"]
  end

  test "a page beyond the last one with no entries is not found" do
    get "/changelog?page=2"
    assert_response :not_found
  end

  test "paginates 30 per page with older and newer links" do
    create_entries(60)
    get "/changelog"
    assert_select ".shiplog-entry", 30
    assert_select "a.shiplog-pagination__link--older[href=?]", "/changelog?page=2"
    assert_select "a.shiplog-pagination__link--newer", 0

    get "/changelog", params: { page: 2 }
    assert_select ".shiplog-entry", 30
    assert_select "a.shiplog-pagination__link--newer[href=?]", "/changelog"
    assert_select "a.shiplog-pagination__link--older[href=?]", "/changelog?page=3"

    get "/changelog", params: { page: 3 }
    assert_select ".shiplog-entry", 1
    assert_select "a.shiplog-pagination__link--older", 0
  end

  test "pagination uses the configured classes" do
    create_entries(31)
    Shiplog.config.classes = { pagination: "flex", pagination_link: "text-indigo-600" }
    get "/changelog"
    assert_select "nav.shiplog-pagination.flex[aria-label] a.shiplog-pagination__link.shiplog-pagination__link--older.text-indigo-600[rel=next]"
  end

  test "page param is clamped and non-numeric means page one" do
    get "/changelog", params: { page: "-4" }
    assert_response :ok
    assert_select ".shiplog-entry__title", text: "Dark mode"
    get "/changelog", params: { page: "abc" }
    assert_select ".shiplog-entry__title", text: "Dark mode"
    get "/changelog", params: { page: "0" }
    assert_select ".shiplog-entry__title", text: "Dark mode"
    get "/changelog", params: { page: { a: 1 } }
    assert_response :ok
    get "/changelog", params: { page: "9" * 40 }
    assert_response :not_found
  end

  test "respects the configured public layout" do
    Shiplog.config.public_layout = "custom"
    get "/changelog"
    assert_select "#host-layout-marker"
  end
end
