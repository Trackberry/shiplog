require "test_helper"

# schema.org JSON-LD on the public pages, through content_for(:shiplog_structured_data).
class Shiplog::StructuredDataTest < ActionDispatch::IntegrationTest
  SELECTOR = "script[type='application/ld+json']".freeze

  setup { @dark = shiplog_entries(:dark_mode_feature) }

  def scripts = css_select(SELECTOR)

  def data
    assert_equal 1, scripts.size, "expected exactly one JSON-LD script"
    JSON.parse(json_text)
  end

  def json_text = scripts.first.children.first.to_s

  def publish(title, released_on, slug: title.parameterize, **attributes)
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: title,
      committed_at: Time.current, url: "https://github.com/x/y/commit/1")
    Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title:, body: "Body", released_on:,
      approved_at: Time.current, slug:, **attributes)
  end

  test "the permalink page is an Article" do
    get "/changelog/dark-mode"
    json = data

    assert_equal "https://schema.org", json["@context"]
    assert_equal "Article", json["@type"]
    assert_equal "Dark mode", json["headline"]
    assert_equal "Switch to a dark theme.", json["description"]
    assert_equal "en", json["inLanguage"]
    assert_equal "2026-10-09", json["datePublished"]
    assert_equal @dark.updated_at.iso8601, json["dateModified"]
    assert_equal "http://www.example.com/changelog/dark-mode", json["url"]
    assert_equal "http://www.example.com/changelog/dark-mode", json["mainEntityOfPage"]
    assert_equal({ "@type" => "CollectionPage", "url" => "http://www.example.com/changelog" }, json["isPartOf"])
  end

  test "the headline is cut at 110 characters and the description like the meta description" do
    publish("Title " * 40, Date.new(2026, 9, 1), slug: "long").update_columns(body: "word " * 100)
    get "/changelog/long"
    json = data

    assert_operator json["headline"].length, :<=, 110
    assert_equal css_select("meta[name=description]").first["content"], json["description"]
  end

  test "a title that closes the script tag cannot break out" do
    @dark.update!(title: "</script><script>alert(1)</script> & <b>", body: "Fish & chips </script>")
    get "/changelog/dark-mode"

    assert_equal 1, scripts.size
    assert_no_match(/[<>&]/, json_text)
    assert_includes response.body, "\\u003c/script\\u003e\\u003cscript\\u003ealert(1)\\u003c/script\\u003e \\u0026 \\u003cb\\u003e"
    assert_equal "</script><script>alert(1)</script> & <b>", JSON.parse(json_text)["headline"]
    assert_equal "Fish & chips </script>", JSON.parse(json_text)["description"]
    assert_equal 1, response.body.scan("<script type=\"application/ld+json\">").size
  end

  test "config.canonical_url sets url and mainEntityOfPage and the changelog URL" do
    Shiplog.config.canonical_url = "https://trackberry.com"
    get "/changelog/dark-mode", headers: { "Host" => "evil.example.net" }
    json = data

    assert_equal "https://trackberry.com/changelog/dark-mode", json["url"]
    assert_equal "https://trackberry.com/changelog/dark-mode", json["mainEntityOfPage"]
    assert_equal "https://trackberry.com/changelog", json["isPartOf"]["url"]
    assert_no_match(/evil\.example\.net/, json_text)
  end

  test "a Spanish translation gives a Spanish headline and inLanguage" do
    Shiplog.config.locales = [ :es ]
    @dark.translations.create!(locale: "es", title: "Modo oscuro", body: "Cambia a un tema oscuro.", source_digest: @dark.translation_source_digest)
    I18n.with_locale(:es) { get "/changelog/dark-mode" }
    json = data

    assert_equal "Modo oscuro", json["headline"]
    assert_equal "Cambia a un tema oscuro.", json["description"]
    assert_equal "es", json["inLanguage"]
  end

  test "image lists the absolute URLs of the screenshots, in order" do
    @dark.add_images([
      { io: StringIO.new(image_bytes(:png)), filename: "first.png", content_type: "image/png" },
      { io: StringIO.new(image_bytes(:gif)), filename: "second.gif", content_type: "image/gif" }
    ])
    get "/changelog/dark-mode"
    images = data["image"]

    assert_equal 2, images.size
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/blobs/redirect/.+/first\.png\z}, images.first
    assert_match(/second\.gif\z/, images.last)
  end

  test "image is omitted without screenshots and while images are off" do
    get "/changelog/dark-mode"
    assert_not data.key?("image")

    @dark.add_images([ { io: StringIO.new(image_bytes(:png)), filename: "first.png", content_type: "image/png" } ])
    Shiplog.config.images = false
    get "/changelog/dark-mode"
    assert_not data.key?("image")
  end

  test "articleSection is the area's display name, omitted without an area" do
    get "/changelog/dark-mode"
    assert_not data.key?("articleSection")

    Shiplog.config.locales = [ :es ]
    @dark.update!(area: Shiplog::Area.create!(name: "Billing", name_translations: { "es" => "Facturación" }))
    get "/changelog/dark-mode"
    assert_equal "Billing", data["articleSection"]
    I18n.with_locale(:es) { get "/changelog/dark-mode" }
    assert_equal "Facturación", data["articleSection"]
  end

  test "publisher is the product name, omitted when unset" do
    get "/changelog/dark-mode"
    assert_not data.key?("publisher")

    Shiplog.config.product_name = "Trackberry"
    get "/changelog/dark-mode"
    assert_equal({ "@type" => "Organization", "name" => "Trackberry" }, data["publisher"])
  end

  test "the changelog list is a CollectionPage with an ItemList of the entries" do
    other = publish("Better CSV", Date.new(2026, 9, 15))
    get "/changelog"
    json = data

    assert_equal "CollectionPage", json["@type"]
    assert_equal "Changelog", json["name"]
    assert_equal "http://www.example.com/changelog", json["url"]
    assert_equal "en", json["inLanguage"]
    assert_equal "ItemList", json["mainEntity"]["@type"]
    assert_equal [
      { "@type" => "ListItem", "position" => 1, "url" => "http://www.example.com/changelog/dark-mode", "name" => "Dark mode" },
      { "@type" => "ListItem", "position" => 2, "url" => "http://www.example.com/changelog/#{other.slug}", "name" => "Better CSV" }
    ], json["mainEntity"]["itemListElement"]
  end

  test "the list only has the entries of the current page, with the page in its URL" do
    now = Time.current
    Shiplog::Entry.insert_all!(Array.new(Shiplog::ChangelogsController::PER_PAGE) do |i|
      { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: 50_000 + i, title: "Bulk #{i}", body: "Body",
        slug: "bulk-#{i}", released_on: Date.new(2026, 8, 1), approved_at: now, created_at: now, updated_at: now }
    end)

    get "/changelog"
    first = data
    assert_equal Shiplog::ChangelogsController::PER_PAGE, first["mainEntity"]["itemListElement"].size
    assert_equal "dark-mode", first["mainEntity"]["itemListElement"].first["url"].split("/").last

    get "/changelog", params: { page: 2 }
    second = data
    assert_equal 1, second["mainEntity"]["itemListElement"].size
    assert_equal "http://www.example.com/changelog?page=2", second["url"]
  end

  test "entries without a valid slug are skipped" do
    publish("No slug", Date.new(2026, 9, 1), slug: nil)
    get "/changelog"
    items = data["mainEntity"]["itemListElement"]

    assert_equal [ "Dark mode" ], items.map { |item| item["name"] }
    assert_equal [ 1 ], items.map { |item| item["position"] }
  end

  test "the list follows the locale" do
    Shiplog.config.locales = [ :es ]
    @dark.translations.create!(locale: "es", title: "Modo oscuro", body: "Texto", source_digest: @dark.translation_source_digest)
    I18n.with_locale(:es) { get "/changelog" }
    json = data

    assert_equal "es", json["inLanguage"]
    assert_equal "Modo oscuro", json["mainEntity"]["itemListElement"].first["name"]
    assert_equal I18n.t("shiplog.changelog.title", locale: :es), json["name"]
  end

  test "search pages and an empty list have no structured data" do
    get "/changelog", params: { q: "dark" }
    assert_response :ok
    assert_select SELECTOR, 0

    Shiplog::Entry.update_all(status: "draft")
    get "/changelog"
    assert_response :ok
    assert_select SELECTOR, 0
  end

  test "the roadmap is a CollectionPage with an ItemList of the cards" do
    get "/roadmap"
    json = data

    assert_equal "CollectionPage", json["@type"]
    assert_equal "Roadmap", json["name"]
    assert_equal "en", json["inLanguage"]
    items = json["mainEntity"]["itemListElement"]
    assert_equal [ "Upload many shipments at once", "Later thing" ].sort, items.map { |item| item["name"] }.sort
    assert_equal (1..items.size).to_a, items.map { |item| item["position"] }
    assert items.none? { |item| item.key?("url") }
  end

  test "the roadmap uses translated card titles" do
    Shiplog.config.locales = [ :es ]
    roadmap = shiplog_entries(:bulk_upload_roadmap)
    roadmap.translations.create!(locale: "es", title: "Sube muchos envíos", body: "Texto", source_digest: roadmap.translation_source_digest)
    I18n.with_locale(:es) { get "/roadmap" }

    assert_includes data["mainEntity"]["itemListElement"].map { |item| item["name"] }, "Sube muchos envíos"
    assert_equal "es", data["inLanguage"]
  end

  test "an empty roadmap has no structured data" do
    Shiplog::Entry.roadmap.update_all(status: "draft")
    get "/roadmap"
    assert_select SELECTOR, 0
  end

  test "config.structured_data = false turns it off everywhere" do
    Shiplog.config.structured_data = false
    %w[/changelog /changelog/dark-mode /roadmap].each do |path|
      get path
      assert_response :ok
      assert_select SELECTOR, 0, path
    end
  end

  test "every public page carries parseable JSON-LD and no missing translations" do
    Shiplog.config.product_name = "Trackberry"
    Shiplog.config.locales = [ :es ]
    %i[en es].each do |locale|
      I18n.with_locale(locale) do
        %w[/changelog /changelog/dark-mode /roadmap].each do |path|
          get path
          assert_response :ok
          assert_equal 1, scripts.size, path
          assert_kind_of Hash, JSON.parse(json_text), path
          assert_no_match(/translation[ _]missing/i, response.body, path)
        end
      end
    end
  end

  test "the page title becomes the CollectionPage name" do
    get "/changelog"
    assert_equal css_select("title").first.text, data["name"]
  end

  test "the setting is part of the render digest" do
    base = Shiplog::Configuration.new.render_digest
    off = Shiplog::Configuration.new.tap { |config| config.structured_data = false }
    assert_not_equal base, off.render_digest
  end

  test "structured_data defaults to true" do
    assert_equal true, Shiplog::Configuration.new.structured_data
  end
end
