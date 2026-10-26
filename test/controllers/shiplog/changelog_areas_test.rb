require "test_helper"
require "rexml/document"

class Shiplog::ChangelogAreasTest < ActionDispatch::IntegrationTest
  ATOM = "http://www.w3.org/2005/Atom".freeze

  setup do
    @billing = Shiplog::Area.create!(name: "Billing")
    @reports = Shiplog::Area.create!(name: "Reports & Exports")
    @dark = shiplog_entries(:dark_mode_feature)
    @csv = shiplog_entries(:csv_change_draft)
    @csv.update!(status: "approved", released_on: Date.new(2026, 9, 15), approved_at: Time.utc(2026, 9, 15), slug: "better-csv-validation",
      body: "Files with unknown headers are rejected.")
    @dark.update!(area: @billing)
    @csv.update!(area: @reports)
  end

  def titles = css_select(".shiplog-entry__title").map(&:text)

  def bulk(count, area: nil, title: "Bulk", released_on: Date.new(2026, 8, 1))
    now = Time.current
    Shiplog::Entry.insert_all!(Array.new(count) do |i|
      { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: 50_000 + i, title: "#{title} #{i}", body: "Body",
        slug: "#{title.parameterize}-#{i}", released_on:, approved_at: now, created_at: now, updated_at: now, area_id: area&.id }
    end)
  end

  test "shows a filter nav with an All link when two areas have published entries" do
    get "/changelog"

    assert_select "nav.shiplog-areas[aria-label=?]", "Filter by area" do
      assert_select "a.shiplog-areas__link", 3
      assert_select "a.shiplog-areas__link--current[href=?]", "/changelog", text: "All"
      assert_select "a.shiplog-areas__link[href=?]", "/changelog?area=billing", text: "Billing"
      assert_select "a.shiplog-areas__link[href=?]", "/changelog?area=reports-exports", text: "Reports & Exports"
    end
  end

  test "the nav follows the admin order" do
    @reports.move(:up)
    get "/changelog"

    assert_equal [ "All", "Reports & Exports", "Billing" ], css_select("nav.shiplog-areas a").map(&:text)
  end

  test "no nav with fewer than two areas that have published entries" do
    @csv.update!(area: @billing)
    get "/changelog"
    assert_select "nav.shiplog-areas", 0

    @csv.update!(area: @reports, status: "draft")
    get "/changelog"
    assert_select "nav.shiplog-areas", 0, "a draft's area does not count"

    @csv.update!(status: "approved", area: @billing)
    shiplog_entries(:bulk_upload_roadmap).update!(area: @reports)
    get "/changelog"
    assert_select "nav.shiplog-areas", 0, "a roadmap entry's area does not count"
  end

  test "no nav when no entry has an area" do
    Shiplog::Entry.update_all(area_id: nil)
    get "/changelog"

    assert_select "nav.shiplog-areas", 0
    assert_select ".shiplog-entry__area", 0
  end

  test "areas without published entries are not listed" do
    Shiplog::Area.create!(name: "Unused")
    get "/changelog"

    assert_select "nav.shiplog-areas a", text: "Unused", count: 0
  end

  test "?area= filters the list and marks the link current" do
    get "/changelog", params: { area: "billing" }

    assert_response :ok
    assert_equal [ "Dark mode" ], titles
    assert_select "a.shiplog-areas__link--current", text: "Billing"
    assert_select "a.shiplog-areas__link--current", text: "All", count: 0
    assert_select "a.shiplog-areas__link[aria-current=page]", text: "Billing"
  end

  test "the area filter combines with search, and the nav and search form keep both" do
    @csv.update!(area: @billing)
    get "/changelog", params: { area: "billing", q: "csv" }

    assert_equal [ "Better CSV validation" ], titles
    assert_select "nav.shiplog-areas", 0, "one visible area only"
    assert_select "form[role=search] input[name=area][value=billing][type=hidden]"

    @csv.update!(area: @reports)
    get "/changelog", params: { area: "billing", q: "csv" }
    assert_empty titles
    assert_select ".shiplog-search__empty"
    get "/changelog", params: { q: "csv" }
    assert_select "a.shiplog-areas__link[href=?]", "/changelog?area=reports-exports&q=csv"
    assert_select "a.shiplog-areas__link[href=?]", "/changelog?q=csv", text: "All"
  end

  test "clearing the search keeps the area" do
    get "/changelog", params: { area: "billing", q: "dark" }

    assert_select "a.shiplog-search__clear[href=?]", "/changelog?area=billing"
  end

  test "pagination links keep the area and the query" do
    bulk(35, area: @billing)
    get "/changelog", params: { area: "billing" }

    assert_equal 30, titles.size
    assert_select "a.shiplog-pagination__link--older[href=?]", "/changelog?area=billing&page=2"

    get "/changelog", params: { area: "billing", q: "bulk", page: 2 }
    assert_equal 5, css_select(".shiplog-entry__title").size
    assert_select "a.shiplog-pagination__link--newer[href=?]", "/changelog?area=billing&q=bulk"
  end

  test "the area is part of the ETag" do
    get "/changelog"
    all = response.headers["ETag"]
    get "/changelog", params: { area: "billing" }
    billing = response.headers["ETag"]
    get "/changelog", params: { area: "reports-exports" }

    assert_not_equal all, billing
    assert_not_equal billing, response.headers["ETag"]

    get "/changelog", params: { area: "billing" }, headers: { "If-None-Match" => billing }
    assert_response :not_modified
  end

  test "renaming, reordering or reassigning an area invalidates cached pages" do
    get "/changelog"
    etag = response.headers["ETag"]

    @billing.update!(name: "Payments")
    get "/changelog", headers: { "If-None-Match" => etag }
    assert_response :ok
    etag = response.headers["ETag"]

    @billing.move(:down)
    get "/changelog", headers: { "If-None-Match" => etag }
    assert_response :ok
    etag = response.headers["ETag"]

    Shiplog::Entry.where(id: @dark.id).update_all(area_id: @reports.id) # no updated_at change
    get "/changelog", headers: { "If-None-Match" => etag }
    assert_response :ok
  end

  test "an unknown area slug is a 404" do
    get "/changelog", params: { area: "nope" }
    assert_response :not_found

    get "/changelog", params: { area: "nope", page: 2 }
    assert_response :not_found
  end

  test "a blank or non-string area is ignored" do
    get "/changelog", params: { area: "" }
    assert_response :ok
    assert_equal 2, titles.size

    get "/changelog?area[]=billing"
    assert_response :ok
    assert_equal 2, titles.size
  end

  test "an existing area with no published entries lists nothing" do
    Shiplog::Area.create!(name: "Unused")
    get "/changelog", params: { area: "unused" }

    assert_response :ok
    assert_select ".shiplog-empty, .shiplog-search__empty"
  end

  test "the filter works with a single area, though the nav is hidden" do
    @csv.update!(area: @billing)
    get "/changelog", params: { area: "billing" }

    assert_equal 2, titles.size
    assert_select "nav.shiplog-areas", 0
  end

  test "each entry shows its area tag, in the list and on the permalink" do
    get "/changelog"
    assert_select "li.shiplog-entry", text: /Dark mode/ do
      assert_select ".shiplog-entry__area", text: "Billing"
    end

    get "/changelog/dark-mode"
    assert_select "article .shiplog-entry__area", text: "Billing"
  end

  test "entries without an area show no tag" do
    @dark.update!(area: nil)
    get "/changelog/dark-mode"

    assert_select ".shiplog-entry__area", 0
  end

  test "the area tag escapes the name" do
    @billing.update_columns(name: "<b>x</b>")
    get "/changelog"

    assert_not_includes response.body, "<b>x</b>"
  end

  test "the permalink ETag follows the area" do
    get "/changelog/dark-mode"
    etag = response.headers["ETag"]
    @billing.update!(name: "Payments")

    get "/changelog/dark-mode", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_select ".shiplog-entry__area", text: "Payments"
  end

  test "roadmap cards show no area" do
    shiplog_entries(:bulk_upload_roadmap).update!(area: @billing)
    get "/roadmap"

    assert_response :ok
    assert_select ".shiplog-entry__area", 0
    assert_not_includes response.body, "Billing"
  end

  test "configured area classes are added" do
    Shiplog.config.classes = { areas: "flex", area_link: "pill", entry_area: "tag" }
    get "/changelog"

    assert_select "nav.shiplog-areas.flex"
    assert_select "a.shiplog-areas__link.pill", 3
    assert_select ".shiplog-entry__area.tag"
  end

  test "the page renders under a locale without translations, with no translation-missing text" do
    I18n.backend.eager_load!
    with_extra_locale(:fr) do
      I18n.backend.store_translations(:fr, date: { month_names: [ nil ] + %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre] })
      get "/changelog"

      assert_response :ok
      assert_no_match(/translation[ _]missing[^"']*shiplog\.changelog\.areas/i, response.body)
      assert_select "nav.shiplog-areas[aria-label=?]", "Filter by area"
      assert_select "nav.shiplog-areas a", text: "All"
    end
  end

  # --- the Atom feed ---

  def feed = REXML::Document.new(response.body)

  def categories(doc)
    REXML::XPath.match(doc, "/a:feed/a:entry", "a" => ATOM).to_h do |entry|
      [ REXML::XPath.first(entry, "a:title", "a" => ATOM).text,
        REXML::XPath.match(entry, "a:category", "a" => ATOM).map { |c| [ c.attributes["term"], c.attributes["label"] ] } ]
    end
  end

  test "the feed adds a category per entry with an area" do
    get "/changelog.atom"

    assert_equal({ "Dark mode" => [ %w[billing Billing] ], "Better CSV validation" => [ [ "reports-exports", "Reports & Exports" ] ] }, categories(feed))
  end

  test "feed entries without an area have no category" do
    @dark.update!(area: nil)
    get "/changelog.atom"

    assert_equal [], categories(feed)["Dark mode"]
  end

  test "the feed honours ?area=" do
    get "/changelog.atom", params: { area: "billing" }

    assert_response :ok
    assert_equal [ "Dark mode" ], categories(feed).keys
  end

  test "the feed answers 404 for an unknown area and has an area-aware ETag" do
    get "/changelog.atom", params: { area: "nope" }
    assert_response :not_found

    get "/changelog.atom"
    all = response.headers["ETag"]
    get "/changelog.atom", params: { area: "billing" }
    assert_not_equal all, response.headers["ETag"]

    @billing.update!(name: "Payments")
    get "/changelog.atom", headers: { "If-None-Match" => all }
    assert_response :ok
  end
end
