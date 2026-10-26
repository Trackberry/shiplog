require "test_helper"
require "rexml/document"

# With config.canonical_url the absolute URLs and the feed's tag URIs no longer depend on the request's host.
class Shiplog::CanonicalUrlTest < ActionDispatch::IntegrationTest
  ATOM = "http://www.w3.org/2005/Atom".freeze
  FORGED = { "X-Forwarded-Host" => "evil.example.net", "Host" => "www.trackberry.com" }.freeze

  def xpath(path) = REXML::XPath.match(REXML::Document.new(response.body), path, "a" => ATOM)

  test "without a canonical URL the request's host is used, as before" do
    get "/changelog.atom"
    assert_equal "http://www.example.com/changelog.atom", xpath("/a:feed/a:link[@rel='self']").first.attributes["href"]
    assert_equal "tag:www.example.com,2005:/changelog/dark-mode", xpath("/a:feed/a:entry/a:id").first.text
  end

  test "the feed's ids and links use the canonical origin, whatever the request host" do
    Shiplog.config.canonical_url = "https://trackberry.com"
    get "/changelog.atom", headers: FORGED

    assert_equal "https://trackberry.com/changelog.atom", xpath("/a:feed/a:link[@rel='self']").first.attributes["href"]
    assert_equal "https://trackberry.com/changelog", xpath("/a:feed/a:link[@rel='alternate']").first.attributes["href"]
    assert_equal "tag:trackberry.com,2005:/changelog", xpath("/a:feed/a:id").first.text
    entry = xpath("/a:feed/a:entry").first
    assert_equal "https://trackberry.com/changelog/dark-mode", REXML::XPath.first(entry, "a:link", "a" => ATOM).attributes["href"]
    assert_equal "tag:trackberry.com,2005:/changelog/dark-mode", REXML::XPath.first(entry, "a:id", "a" => ATOM).text
    assert_no_match(/evil\.example\.net|www\.trackberry\.com|example\.com/, response.body)
  end

  test "a canonical URL with a port keeps it in links, not in the tag host" do
    Shiplog.config.canonical_url = "http://localhost:3000"
    get "/changelog.atom"
    assert_equal "http://localhost:3000/changelog/dark-mode", xpath("/a:feed/a:entry/a:link").first.attributes["href"]
    assert_equal "tag:localhost,2005:/changelog/dark-mode", xpath("/a:feed/a:entry/a:id").first.text
  end

  test "the permalink page's og:url and feed link are canonical" do
    Shiplog.config.canonical_url = "https://trackberry.com"
    get "/changelog/dark-mode", headers: FORGED
    assert_select "meta[property='og:url'][content=?]", "https://trackberry.com/changelog/dark-mode"
    assert_select "link[rel=alternate][type='application/atom+xml'][href=?]", "https://trackberry.com/changelog.atom"
    assert_no_match(/evil\.example\.net|www\.trackberry\.com/, response.body)
  end

  test "the changelog list's feed link is canonical" do
    Shiplog.config.canonical_url = "https://trackberry.com"
    get "/changelog", headers: FORGED
    assert_select "link[rel=alternate][type='application/atom+xml'][href=?]", "https://trackberry.com/changelog.atom"
  end

  test "the feed and permalink ETags follow the canonical URL and the product name" do
    [ "/changelog.atom", "/changelog/dark-mode" ].each do |path|
      get path
      plain = response.headers["ETag"]

      Shiplog.config.canonical_url = "https://trackberry.com"
      get path, headers: { "If-None-Match" => plain }
      assert_response :ok, path
      canonical = response.headers["ETag"]
      assert_not_equal plain, canonical

      Shiplog.config.product_name = "Acme"
      get path, headers: { "If-None-Match" => canonical }
      assert_response :ok, path
      assert_not_equal canonical, response.headers["ETag"]
    ensure
      Shiplog.reset_config!
    end
  end
end
