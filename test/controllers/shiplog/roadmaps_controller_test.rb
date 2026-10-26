require "test_helper"

class Shiplog::RoadmapsControllerTest < ActionDispatch::IntegrationTest
  test "renders three columns with translated headings" do
    get "/roadmap"
    assert_response :ok
    assert_select "section.shiplog-column[aria-labelledby]", 3
    assert_select "h2.shiplog-column__title", text: "In progress"
    assert_select "h2.shiplog-column__title", text: "Coming soon"
    assert_select "h2.shiplog-column__title", text: "Later"
  end

  test "shows approved entry titles and bodies" do
    get "/roadmap"
    assert_select "li.shiplog-card .shiplog-card__title", text: "Upload many shipments at once"
    assert_select "li.shiplog-card .shiplog-card__title", text: "Later thing"
    assert_includes response.body, "Soon you will be able to import a spreadsheet."
  end

  test "never leaks drafts or GitHub details" do
    get "/roadmap"
    assert_not_includes response.body, "Soon thing"
    assert_not_includes response.body, "Draft text."
    assert_not_includes response.body, "Bulk upload"
    assert_not_includes response.body, "github.com"
    assert_not_includes response.body, "#1"
  end

  test "empty columns say there is nothing yet" do
    Shiplog::Entry.roadmap.update_all(status: "draft")
    get "/roadmap"
    assert_select "p.shiplog-column__empty", text: "Nothing here yet", count: 3
    assert_select ".shiplog-column__count", text: "0", count: 3
  end

  test "escapes HTML in bodies" do
    shiplog_entries(:later_item_roadmap).update!(body: "<script>alert(1)</script>\n\nSecond paragraph")
    get "/roadmap"
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_select ".shiplog-card__body p", minimum: 2
  end

  test "uses the default stylesheet layout" do
    get "/roadmap"
    assert_select "link[rel=stylesheet][href=?]", "/shiplog/assets/#{Shiplog::VERSION}/shiplog.css", count: 1
    assert_select "main .shiplog-page.shiplog-page--roadmap"
  end

  test "the stylesheet link is emitted by the page, inside the body" do
    get "/roadmap"
    assert_select "head link[rel=stylesheet]", 0
    assert_select "body link[rel=stylesheet][href*='shiplog.css']", 1
  end

  test "the stylesheet link is also emitted inside a host layout" do
    Shiplog.config.public_layout = "custom"
    get "/roadmap"
    assert_select "link[rel=stylesheet][href*='shiplog.css']", 1
  end

  test "stylesheet false leaves out the bundled stylesheet" do
    Shiplog.config.stylesheet = false
    get "/roadmap"
    assert_select "link[rel=stylesheet]", 0
    assert_select ".shiplog-page"
  end

  test "page header has a title and a lede" do
    get "/roadmap"
    assert_select "header.shiplog-page__header h1.shiplog-page__title", text: "Roadmap"
    assert_select "header.shiplog-page__header p.shiplog-page__lede", text: /working on/
  end

  test "column headers show a count and a description" do
    get "/roadmap"
    assert_select "section.shiplog-column--in-progress header.shiplog-column__header" do
      assert_select ".shiplog-column__title", text: "In progress"
      assert_select ".shiplog-column__count", text: "1"
      assert_select ".shiplog-column__description", text: "What we're building now"
    end
    assert_select "section.shiplog-column--coming-soon .shiplog-column__description", text: "Planned next"
    assert_select "section.shiplog-column--later .shiplog-column__description", text: "On our radar"
  end

  test "columns are sections labelled by their title and hold ordered cards" do
    get "/roadmap"
    assert_select "section.shiplog-column[aria-labelledby=shiplog-column-later] h2#shiplog-column-later"
    assert_select "section.shiplog-column--later ol.shiplog-cards li.shiplog-card", 1
  end

  test "configured classes are added next to the BEM classes" do
    Shiplog.config.classes = { columns: "grid gap-6 md:grid-cols-3", card: "rounded-lg border", page_title: "text-3xl" }
    get "/roadmap"
    assert_select "div.shiplog-columns.grid.gap-6.md\\:grid-cols-3"
    assert_select "li.shiplog-card.rounded-lg.border"
    assert_select "h1.shiplog-page__title.text-3xl"
  end

  test "respects the configured public layout" do
    Shiplog.config.public_layout = "custom"
    get "/roadmap"
    assert_select "#host-layout-marker"
    assert_select "section.shiplog-column", 3
  end

  test "responds with conditional GET caching" do
    get "/roadmap"
    etag = response.headers["ETag"]
    assert etag.present?
    get "/roadmap", headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "ETag changes after approving an entry" do
    get "/roadmap"
    etag = response.headers["ETag"]
    shiplog_entries(:soon_item_roadmap).approve!(by: "ed@example.com")
    get "/roadmap", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes after pinning an issue to another column" do
    get "/roadmap"
    etag = response.headers["ETag"]
    shiplog_issues(:later_item).update_columns(pinned_column: "in_progress")
    get "/roadmap", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes when config.classes changes" do
    get "/roadmap"
    etag = response.headers["ETag"]
    Shiplog.config.classes = { card: "rounded" }
    get "/roadmap"
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes when config.stylesheet changes" do
    get "/roadmap"
    etag = response.headers["ETag"]
    Shiplog.config.stylesheet = false
    get "/roadmap"
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes with the gem version" do
    get "/roadmap"
    etag = response.headers["ETag"]
    original = Shiplog::VERSION
    begin
      silence_warnings { Shiplog.const_set(:VERSION, "9.9.9") }
      get "/roadmap"
      assert_not_equal etag, response.headers["ETag"]
    ensure
      silence_warnings { Shiplog.const_set(:VERSION, original) }
    end
  end

  test "ETag differs per locale" do
    get "/roadmap"
    english = response.headers["ETag"]
    with_extra_locale(:fr) { get "/roadmap" }
    assert_not_equal english, response.headers["ETag"]
  end
end
