require "test_helper"
require "rexml/document"

# An entry whose stored slug the route rejects (written by older code, or by hand) must not break the pages
# that list or link to it: it renders without a link.
class Shiplog::BadSlugRenderingTest < ActionDispatch::IntegrationTest
  ATOM = "http://www.w3.org/2005/Atom".freeze

  setup { shiplog_entries(:dark_mode_feature).update_columns(slug: "support-for-snake_case-keys") }

  test "the changelog list renders the entry without a link" do
    get "/changelog"
    assert_response :ok
    assert_select "h3", text: "Dark mode"
    assert_select "h3 a", text: "Dark mode", count: 0
  end

  test "a neighbour with a bad slug is shown without a link on a permalink page" do
    now = Time.current
    Shiplog::Entry.insert_all!([ { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: 30_000, title: "Newer entry",
      body: "Body", slug: "newer-entry", released_on: Date.new(2026, 10, 20), approved_at: now, created_at: now, updated_at: now } ])
    get "/changelog/newer-entry"
    assert_response :ok
    assert_select "nav.shiplog-permalink__nav a", count: 0
    assert_select "nav.shiplog-permalink__nav", text: /Dark mode/
  end

  test "the feed skips the entry instead of raising" do
    get "/changelog.atom"
    assert_response :ok
    doc = REXML::Document.new(response.body)
    titles = REXML::XPath.match(doc, "/a:feed/a:entry/a:title", "a" => ATOM).map(&:text)
    assert_not_includes titles, "Dark mode"
  end
end
