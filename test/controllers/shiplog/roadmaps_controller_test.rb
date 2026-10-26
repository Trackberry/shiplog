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
    assert_select ".shiplog-entry__title", text: "Upload many shipments at once"
    assert_select ".shiplog-entry__title", text: "Later thing"
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
    assert_select ".shiplog-column__empty", text: "Nothing here yet", count: 3
  end

  test "escapes HTML in bodies" do
    shiplog_entries(:later_item_roadmap).update!(body: "<script>alert(1)</script>\n\nSecond paragraph")
    get "/roadmap"
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_select ".shiplog-entry__body p", minimum: 2
  end

  test "uses the default stylesheet layout" do
    get "/roadmap"
    assert_select "link[rel=stylesheet][href=?]", "/shiplog/assets/#{Shiplog::VERSION}/shiplog.css"
    assert_select "main .shiplog-roadmap.shiplog"
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

  test "ETag differs per locale" do
    get "/roadmap"
    english = response.headers["ETag"]
    with_extra_locale(:fr) { get "/roadmap" }
    assert_not_equal english, response.headers["ETag"]
  end
end
