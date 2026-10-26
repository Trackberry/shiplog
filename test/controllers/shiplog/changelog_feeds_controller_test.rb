require "test_helper"
require "rexml/document"

class Shiplog::ChangelogFeedsControllerTest < ActionDispatch::IntegrationTest
  ATOM = "http://www.w3.org/2005/Atom".freeze

  def bulk(count, offset: 20_000)
    now = Time.current
    Shiplog::Entry.insert_all!(Array.new(count) do |i|
      { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: offset + i, title: "Bulk #{i}", body: "Body #{i}",
        slug: "bulk-#{i}", released_on: Date.new(2026, 9, 1) - i, approved_at: now, created_at: now, updated_at: now }
    end)
  end

  def feed
    REXML::Document.new(response.body)
  end

  def xpath(doc, path) = REXML::XPath.match(doc, path, "a" => ATOM)

  test "serves valid Atom with the right content type" do
    get "/changelog.atom"
    assert_response :ok
    assert_equal "application/atom+xml", response.media_type

    doc = feed
    assert_equal "feed", doc.root.name
    assert_equal ATOM, doc.root.namespace
    assert_equal "Changelog", xpath(doc, "/a:feed/a:title").first.text
    assert_equal "http://www.example.com/changelog.atom", xpath(doc, "/a:feed/a:link[@rel='self']").first.attributes["href"]
    assert_equal "http://www.example.com/changelog", xpath(doc, "/a:feed/a:link[@rel='alternate']").first.attributes["href"]
    assert xpath(doc, "/a:feed/a:updated").first.text.present?
    assert xpath(doc, "/a:feed/a:id").first.text.present?
  end

  test "an entry has id, title, links, dates and HTML content" do
    get "/changelog.atom"
    entry = xpath(feed, "/a:feed/a:entry").first

    assert_equal "Dark mode", REXML::XPath.first(entry, "a:title", "a" => ATOM).text
    assert_equal "http://www.example.com/changelog/dark-mode", REXML::XPath.first(entry, "a:link", "a" => ATOM).attributes["href"]
    assert_equal "tag:www.example.com,2005:/changelog/dark-mode", REXML::XPath.first(entry, "a:id", "a" => ATOM).text
    assert_equal "2026-10-09", REXML::XPath.first(entry, "a:published", "a" => ATOM).text[0, 10]
    assert_match(/\A\d{4}-\d\d-\d\dT/, REXML::XPath.first(entry, "a:updated", "a" => ATOM).text)
    content = REXML::XPath.first(entry, "a:content", "a" => ATOM)
    assert_equal "html", content.attributes["type"]
    assert_equal "<p>Switch to a dark theme.</p>", content.text
  end

  test "html in a title or body is escaped, not interpreted" do
    shiplog_entries(:dark_mode_feature).update_columns(title: "A <b>bold</b> & co", body: "<script>alert(1)</script>")
    get "/changelog.atom"
    entry = xpath(feed, "/a:feed/a:entry").first
    assert_equal "A <b>bold</b> & co", REXML::XPath.first(entry, "a:title", "a" => ATOM).text
    assert_equal "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>", REXML::XPath.first(entry, "a:content", "a" => ATOM).text
  end

  test "lists only approved features and changes, newest first, at most 50" do
    bulk(60)
    get "/changelog.atom"
    titles = xpath(feed, "/a:feed/a:entry/a:title").map(&:text)

    assert_equal 50, titles.size
    assert_equal "Dark mode", titles.first
    assert_not_includes titles, "Better CSV validation"
    assert_not_includes titles, "Typo fix"
    assert_not_includes titles, "Upload many shipments at once"
  end

  test "every link and id is absolute and the ids are unique" do
    bulk(5)
    get "/changelog.atom"
    doc = feed
    hrefs = xpath(doc, "/a:feed/a:entry/a:link").map { |link| link.attributes["href"] }
    assert hrefs.all? { |href| href.start_with?("http://www.example.com/changelog/") }
    ids = xpath(doc, "/a:feed/a:entry/a:id").map(&:text)
    assert_equal ids.uniq, ids
  end

  test "entry ids do not change when the title changes or the entry is fetched again" do
    get "/changelog.atom"
    before = xpath(feed, "/a:feed/a:entry/a:id").map(&:text)
    shiplog_entries(:dark_mode_feature).update!(title: "Dark mode, reworked")
    get "/changelog.atom"
    assert_equal before, xpath(feed, "/a:feed/a:entry/a:id").map(&:text)
  end

  test "entries without a slug get one" do
    shiplog_entries(:dark_mode_feature).update_columns(slug: nil)
    get "/changelog.atom"
    assert_equal "http://www.example.com/changelog/dark-mode", xpath(feed, "/a:feed/a:entry/a:link").first.attributes["href"]
  end

  test "the product name titles the feed" do
    Shiplog.config.product_name = "Acme"
    get "/changelog.atom"
    assert_equal "Acme changelog", xpath(feed, "/a:feed/a:title").first.text
  end

  test "an empty changelog is still a valid feed" do
    Shiplog::Entry.where(kind: %w[feature change]).delete_all
    get "/changelog.atom"
    assert_response :ok
    assert_empty xpath(feed, "/a:feed/a:entry")
    assert xpath(feed, "/a:feed/a:updated").first.text.present?
  end

  test "a matching ETag answers 304 and an edit changes it" do
    get "/changelog.atom"
    etag = response.headers["ETag"]
    assert etag

    get "/changelog.atom", headers: { "If-None-Match" => etag }
    assert_response :not_modified

    travel(1.minute) { shiplog_entries(:dark_mode_feature).update!(body: "Changed") }
    get "/changelog.atom", headers: { "If-None-Match" => etag }
    assert_response :ok
  end

  test "the changelog page advertises the feed" do
    get "/changelog"
    assert_select "link[rel=alternate][type='application/atom+xml'][href=?]", "http://www.example.com/changelog.atom"
    assert_select "a.shiplog-footnote__link[href=?]", "/changelog.atom", text: "Subscribe (Atom)"
  end

  test "the feed renders under another locale without translation-missing text" do
    with_extra_locale(:fr) do
      get "/changelog.atom"
      assert_response :ok
      assert_no_match(/translation[ _]missing/i, response.body)
    end
  end

  test "on_changelog_seen is not called for the feed" do
    called = false
    Shiplog.config.on_changelog_seen = ->(_controller) { called = true }
    get "/changelog.atom"
    assert_response :ok
    assert_not called
  end
end
