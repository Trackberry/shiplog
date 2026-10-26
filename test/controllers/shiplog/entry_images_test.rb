require "test_helper"
require "rexml/document"

# Screenshots on the public pages: the list (first image), the permalink (all), Open Graph, the Atom feed, ETags.
class Shiplog::EntryImagesTest < ActionDispatch::IntegrationTest
  ATOM = "http://www.w3.org/2005/Atom".freeze

  setup do
    @entry = shiplog_entries(:dark_mode_feature)
    @png, @gif = @entry.add_images([
      { io: StringIO.new(image_bytes(:png)), filename: "first.png", content_type: "image/png" },
      { io: StringIO.new(image_bytes(:gif)), filename: "second.gif", content_type: "image/gif" }
    ])
  end

  def srcs(selector) = css_select(selector).map { |img| img["src"] }

  def feed_content
    doc = REXML::Document.new(response.body)
    Nokogiri::HTML.fragment(REXML::XPath.first(doc, "/a:feed/a:entry/a:content", "a" => ATOM).text)
  end

  def analyze(attachment, width:, height:)
    blob = attachment.blob
    blob.update!(metadata: blob.metadata.merge(analyzed: true, width:, height:))
  end

  test "the changelog list shows the first image under the body, and only that one" do
    get "/changelog"

    assert_select "li.shiplog-entry .shiplog-entry__images img.shiplog-entry__image", 1
    assert_match %r{\A/rails/active_storage/blobs/redirect/.+/first\.png\z}, srcs(".shiplog-entry__image").first
    assert_select ".shiplog-entry__body + .shiplog-entry__images"
    assert_select "img.shiplog-entry__image[loading=lazy][alt=?]", "Dark mode"
  end

  test "the permalink shows all the images in order" do
    get "/changelog/dark-mode"

    assert_select "article .shiplog-entry__images img.shiplog-entry__image", 2
    assert_match(/first\.png\z/, srcs(".shiplog-entry__image").first)
    assert_match(/second\.gif\z/, srcs(".shiplog-entry__image").last)
  end

  test "entries without images render no container" do
    get "/changelog"
    assert_select ".shiplog-entry__images", 1 # only the entry that has images
    @entry.images.each(&:purge)
    get "/changelog"
    assert_select ".shiplog-entry__images", 0
  end

  test "the order and alt texts of the admin are used" do
    @entry.move_image(@gif.blob_id, :up)
    @entry.update_image_alt(@gif.blob_id, "The settings screen")
    get "/changelog/dark-mode"

    assert_match(/second\.gif\z/, srcs(".shiplog-entry__image").first)
    assert_equal [ "The settings screen", "Dark mode" ], css_select(".shiplog-entry__image").map { |img| img["alt"] }
  end

  test "width and height come from the analysed blob, when present" do
    get "/changelog/dark-mode"
    assert_select "img.shiplog-entry__image[width]", 0

    analyze(@png, width: 640, height: 480)
    get "/changelog/dark-mode"
    assert_select "img.shiplog-entry__image[width='640'][height='480']", 1
    assert_select "img.shiplog-entry__image[width]", 1
  end

  test "the image is served through the host's Active Storage routes" do
    get "/changelog/dark-mode"
    get srcs(".shiplog-entry__image").first
    assert_response :redirect

    follow_redirect!
    assert_response :ok
    assert_equal image_bytes(:png), response.body.b
  end

  test "config.classes add classes to the container and the images" do
    Shiplog.config.classes = { entry_images: "grid", entry_image: "rounded" }
    get "/changelog/dark-mode"
    assert_select "div.shiplog-entry__images.grid img.shiplog-entry__image.rounded", 2
  end

  test "the Open Graph image is the first image's absolute URL" do
    get "/changelog/dark-mode"
    assert_select "meta[property='og:image'][content^=?]", "http://www.example.com/rails/active_storage/blobs/redirect/"
    assert_select "meta[property='og:image'][content$=?]", "/first.png"
  end

  test "config.canonical_url makes the image URLs absolute against it" do
    Shiplog.config.canonical_url = "https://example.com"
    get "/changelog/dark-mode"
    assert_select "meta[property='og:image'][content^=?]", "https://example.com/rails/active_storage/blobs/redirect/"

    get "/changelog.atom"
    assert feed_content.css("img").all? { |img| img["src"].start_with?("https://example.com/rails/active_storage/blobs/") }
  end

  test "an entry without images has no og:image" do
    get "/changelog/dark-mode"
    assert_select "meta[property='og:image']", 1
    @entry.images.each(&:purge)
    get "/changelog/dark-mode"
    assert_select "meta[property='og:image']", 0
  end

  test "the Atom feed includes the images with absolute URLs and alt texts" do
    @entry.update_image_alt(@png.blob_id, "Dark theme")
    analyze(@png, width: 10, height: 20)
    get "/changelog.atom"

    images = feed_content.css("img")
    assert_equal 2, images.size
    assert images.all? { |img| img["src"].start_with?("http://www.example.com/rails/active_storage/blobs/") }
    assert_equal [ "Dark theme", "Dark mode" ], images.map { |img| img["alt"] }
    assert_equal [ "10", "20" ], [ images.first["width"], images.first["height"] ]
    assert_includes feed_content.text, "Switch to a dark theme."
  end

  test "the ETag changes with the images' order, alt texts and blobs, even when updated_at does not" do
    get "/changelog/dark-mode"
    etag = response.headers["ETag"]
    get "/changelog/dark-mode", headers: { "If-None-Match" => etag }
    assert_response :not_modified

    @entry.update_columns(image_order: [ @gif.blob_id, @png.blob_id ])
    get "/changelog/dark-mode", headers: { "If-None-Match" => etag }
    assert_response :ok
    order_etag = response.headers["ETag"]
    assert_not_equal etag, order_etag

    @entry.update_columns(image_alts: { @gif.blob_id.to_s => "Other" })
    get "/changelog/dark-mode", headers: { "If-None-Match" => order_etag }
    assert_response :ok
    alt_etag = response.headers["ETag"]

    @entry.reload.ordered_images.last.update_columns(blob_id: ActiveStorage::Blob.create_and_upload!(io: StringIO.new(image_bytes(:jpg)), filename: "x.jpg", content_type: "image/jpeg", identify: false).id)
    get "/changelog/dark-mode", headers: { "If-None-Match" => alt_etag }
    assert_response :ok
    assert_not_equal alt_etag, response.headers["ETag"]
  end

  test "the list and the feed ETags include the images too" do
    [ "/changelog", "/changelog.atom" ].each do |path|
      get path
      etag = response.headers["ETag"]
      @entry.update_columns(image_alts: { @png.blob_id.to_s => "New alt #{path}" })
      get path, headers: { "If-None-Match" => etag }
      assert_response :ok, path
      assert_not_equal etag, response.headers["ETag"], path
    end
  end

  test "config.images is part of the ETag" do
    get "/changelog/dark-mode"
    etag = response.headers["ETag"]
    Shiplog.config.images = false
    get "/changelog/dark-mode", headers: { "If-None-Match" => etag }
    assert_response :ok
  end

  test "the list does not query per entry for images" do
    get "/changelog"
    baseline = count_queries { get "/changelog" }
    other = Shiplog::Entry.create!(kind: "change", status: "approved", subject: shiplog_pull_requests(:dark_mode_pr), title: "Another", body: "x", released_on: Date.new(2026, 10, 8), approved_at: Time.current)
    other.add_images([ { io: StringIO.new(image_bytes(:png)), filename: "o.png", content_type: "image/png" } ])
    assert_equal baseline, count_queries { get "/changelog" }
  end

  test "with config.images = false nothing is rendered" do
    Shiplog.config.images = false

    get "/changelog"
    assert_select ".shiplog-entry__images", 0
    get "/changelog/dark-mode"
    assert_select ".shiplog-entry__images", 0
    assert_select "meta[property='og:image']", 0
    get "/changelog.atom"
    assert_empty feed_content.css("img")
  end

  test "without Active Storage nothing is rendered and nothing crashes" do
    without_active_storage do
      get "/changelog"
      assert_response :ok
      assert_select ".shiplog-entry__images", 0
      get "/changelog/dark-mode"
      assert_response :ok
      assert_select "meta[property='og:image']", 0
      get "/changelog.atom"
      assert_response :ok
      assert_empty feed_content.css("img")
    end
  end

  test "no translation is missing under a host locale without Shiplog translations" do
    with_extra_locale(:fr) do
      I18n.backend.store_translations(:fr, date: { month_names: [ nil ] + %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre] })
      [ "/changelog", "/changelog/dark-mode", "/changelog.atom", "/admin/shiplog/entries/#{shiplog_entries(:csv_change_draft).id}/edit" ].each do |path|
        get path
        assert_response :ok, path
        assert_no_match(/translation missing: [^"']*images/i, response.body, path)
        assert_no_match(/class="translation_missing"[^>]*>[^<]*(Images|Screenshots)/i, response.body, path)
      end
      get "/admin/shiplog/entries/#{@entry.id}/edit"
      assert_select ".shiplog-admin-images h2", "Screenshots"
      assert_select ".shiplog-admin-images input[type=submit][value=?]", "Upload images"
      assert_select ".shiplog-admin-images button, .shiplog-admin-images input[type=submit]", text: /Remove|Save alt text/, minimum: 1
    end
  end
end
