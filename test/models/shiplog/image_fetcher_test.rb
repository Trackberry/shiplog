require "test_helper"

class Shiplog::ImageFetcherTest < ActiveJob::TestCase
  GRAPHQL = "https://api.github.com/graphql".freeze
  SIGNED = "https://private-user-images.githubusercontent.com/1/abc.png?jwt=secret".freeze

  setup do
    Shiplog.config.github_token = "tok"
    @entry = shiplog_entries(:csv_change_draft)
  end

  def stub_body(html)
    stub_request(:post, GRAPHQL).to_return(body: { data: { node: { bodyHTML: html } } }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def img(url) = %(<p><img src="#{CGI.escapeHTML(url)}" alt="shot"></p>)

  def stub_image(url, body = image_bytes(:png), **options) = stub_request(:get, url).to_return(status: 200, body:, **options)

  def fetch = Shiplog::ImageFetcher.call(@entry)

  test "attaches an image from the body, in order, with its type taken from its bytes" do
    stub_body(img(SIGNED) + img("https://user-images.githubusercontent.com/2/b.gif"))
    stub_image(SIGNED)
    stub_image("https://user-images.githubusercontent.com/2/b.gif", image_bytes(:gif))

    assert_equal 2, fetch

    images = @entry.reload.ordered_images
    assert_equal %w[image/png image/gif], images.map { |image| image.blob.content_type }
    assert_equal %w[screenshot-1.png screenshot-2.gif], images.map { |image| image.blob.filename.to_s }
    assert_equal images.map(&:blob_id), @entry.image_order
    assert_equal @entry.title, @entry.image_alt(images.first)
  end

  test "the GraphQL query asks for the body HTML of the subject's node id" do
    stub_body(img(SIGNED))
    stub_image(SIGNED)
    fetch
    assert_requested(:post, GRAPHQL) { |request| JSON.parse(request.body).then { |body| body["query"].include?("bodyHTML") && body["variables"] == { "id" => "PR_typo_fix" } } }
  end

  test "only the allowlisted hosts are fetched: exact host, https, user-attachments path" do
    skipped = [
      "https://user-images.githubusercontent.com.evil.com/a.png",
      "https://evil.com/user-images.githubusercontent.com/a.png",
      "https://user-images.githubusercontent.com@evil.com/a.png",
      "http://user-images.githubusercontent.com/a.png",
      "https://github.com/acme/app/raw/main/a.png",
      "https://github.com/user-attachments/files/1/a.png",
      "https://github.com.evil.com/user-attachments/assets/a",
      "https://user-images.githubusercontent.com:8443/a.png",
      "data:image/png;base64,AAAA",
      "/relative.png"
    ]
    stub_body(skipped.map { |url| img(url) }.join)
    stub_request(:any, /.*/).to_raise("a request must not be made")

    assert_equal 0, fetch
    assert_not_requested :get, /.*/
    assert_not @entry.reload.images.attached?
  end

  test "every allowlisted host is fetched" do
    urls = %w[
      https://private-user-images.githubusercontent.com/1/a.png https://user-images.githubusercontent.com/2/b.png
      https://github.com/user-attachments/assets/aaaa https://camo.githubusercontent.com/abc
    ]
    Shiplog.config.max_images_per_entry = 5
    stub_body(urls.map { |url| img(url) }.join + img("https://raw.githubusercontent.com/acme/app/main/c.png"))
    (urls + [ "https://raw.githubusercontent.com/acme/app/main/c.png" ]).each { |url| stub_image(url) }

    assert_equal 5, fetch
  end

  test "a redirect off the allowlist is not followed" do
    stub_body(img(SIGNED))
    stub_request(:get, SIGNED).to_return(status: 302, headers: { "Location" => "https://evil.com/a.png" })
    evil = stub_image("https://evil.com/a.png")

    assert_equal 0, fetch
    assert_not_requested evil
  end

  test "a redirect to http is not followed" do
    stub_body(img(SIGNED))
    stub_request(:get, SIGNED).to_return(status: 302, headers: { "Location" => "http://user-images.githubusercontent.com/a.png" })
    assert_equal 0, fetch
  end

  test "redirects within the allowlist are followed, up to three" do
    stub_body(img("https://github.com/user-attachments/assets/aaaa"))
    stub_request(:get, "https://github.com/user-attachments/assets/aaaa").to_return(status: 302, headers: { "Location" => "https://objects.githubusercontent.com/x" })
    stub_request(:get, "https://objects.githubusercontent.com/x").to_return(status: 302, headers: { "Location" => "/y" })
    stub_request(:get, "https://objects.githubusercontent.com/y").to_return(status: 301, headers: { "Location" => "https://private-user-images.githubusercontent.com/z" })
    stub_image("https://private-user-images.githubusercontent.com/z")

    assert_equal 1, fetch
  end

  test "a fourth redirect fails" do
    stub_body(img(SIGNED))
    stub_request(:get, SIGNED).to_return(status: 302, headers: { "Location" => "https://objects.githubusercontent.com/1" })
    stub_request(:get, "https://objects.githubusercontent.com/1").to_return(status: 302, headers: { "Location" => "https://objects.githubusercontent.com/2" })
    stub_request(:get, "https://objects.githubusercontent.com/2").to_return(status: 302, headers: { "Location" => "https://objects.githubusercontent.com/3" })
    stub_request(:get, "https://objects.githubusercontent.com/3").to_return(status: 302, headers: { "Location" => "https://objects.githubusercontent.com/4" })
    final = stub_image("https://objects.githubusercontent.com/4")

    assert_equal 0, fetch
    assert_not_requested final
  end

  test "the token goes to github.com only, never to the other hosts, also across a redirect" do
    stub_body(img("https://github.com/user-attachments/assets/aaaa") + img(SIGNED))
    stub_request(:get, "https://github.com/user-attachments/assets/aaaa").to_return(status: 302, headers: { "Location" => "https://private-user-images.githubusercontent.com/z" })
    stub_image("https://private-user-images.githubusercontent.com/z")
    stub_image(SIGNED)

    assert_equal 2, fetch

    assert_requested(:get, "https://github.com/user-attachments/assets/aaaa", headers: { "Authorization" => "Bearer tok" })
    assert_requested(:get, "https://private-user-images.githubusercontent.com/z") { |request| !request.headers.key?("Authorization") }
    assert_requested(:get, SIGNED) { |request| !request.headers.key?("Authorization") }
  end

  test "an image larger than 5 MB is dropped while streaming" do
    stub_body(img(SIGNED))
    stub_image(SIGNED, image_bytes(:png) + ("a" * Shiplog::ImageType::MAX_BYTES))
    assert_equal 0, fetch
    assert_not @entry.reload.images.attached?
  end

  test "an image of exactly 5 MB is kept" do
    stub_body(img(SIGNED))
    stub_image(SIGNED, image_bytes(:png).ljust(Shiplog::ImageType::MAX_BYTES, "a"))
    assert_equal 1, fetch
  end

  test "a declared length over 5 MB is refused" do
    stub_body(img(SIGNED))
    stub_image(SIGNED, image_bytes(:png), headers: { "Content-Length" => (Shiplog::ImageType::MAX_BYTES + 1).to_s })
    assert_equal 0, fetch
  end

  test "SVG, HTML and unknown bytes are refused whatever the URL and content type say" do
    urls = %w[a.png b.png c.svg].map { |name| "https://user-images.githubusercontent.com/#{name}" }
    stub_body(urls.map { |url| img(url) }.join)
    stub_image(urls[0], image_bytes(:svg), headers: { "Content-Type" => "image/png" })
    stub_image(urls[1], image_bytes(:html), headers: { "Content-Type" => "image/png" })
    stub_image(urls[2], "", headers: { "Content-Type" => "image/png" })

    assert_equal 0, fetch
  end

  test "at most max_images_per_entry images are fetched" do
    urls = (1..6).map { |i| "https://user-images.githubusercontent.com/#{i}.png" }
    stub_body(urls.map { |url| img(url) }.join)
    urls.each { |url| stub_image(url) }

    assert_equal 4, fetch
    assert_equal 4, @entry.reload.images.count
    assert_not_requested :get, urls[4]

    Shiplog.config.max_images_per_entry = 2
    other = shiplog_entries(:soon_item_roadmap)
    assert_equal 0, Shiplog::ImageFetcher.call(other) # roadmap entries never get images
  end

  test "the same image twice is fetched once" do
    stub_body(img(SIGNED) + img(SIGNED))
    request = stub_image(SIGNED)
    assert_equal 1, fetch
    assert_requested request, times: 1
  end

  test "an image that fails does not stop the others" do
    first = "https://user-images.githubusercontent.com/1.png"
    second = "https://user-images.githubusercontent.com/2.png"
    third = "https://user-images.githubusercontent.com/3.png"
    stub_body([ first, second, third ].map { |url| img(url) }.join)
    stub_request(:get, first).to_timeout
    stub_request(:get, second).to_return(status: 404)
    stub_image(third)

    assert_equal 1, fetch
    assert_equal 1, @entry.reload.images.count
  end

  test "connections have five second timeouts and the limits are 3 redirects and 5 MB" do
    stub_body(img(SIGNED))
    stub_image(SIGNED)
    connections = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*args| original.call(*args).tap { |http| connections << http } }
    begin
      fetch
    ensure
      Net::HTTP.singleton_class.remove_method(:new)
    end

    image_connection = connections.find { |http| http.address == "private-user-images.githubusercontent.com" }
    assert_equal [ 5, 5 ], [ image_connection.open_timeout, image_connection.read_timeout ]
    assert image_connection.use_ssl?
    assert_equal 3, Shiplog::ImageFetcher::Downloader::MAX_REDIRECTS
    assert_equal 5.megabytes, Shiplog::ImageType::MAX_BYTES
  end

  test "GitHub failures are logged and return zero" do
    stub_request(:post, GRAPHQL).to_return(status: 500)
    assert_equal 0, fetch

    stub_request(:post, GRAPHQL).to_timeout
    assert_equal 0, fetch

    Shiplog.config.github_token = nil
    assert_equal 0, fetch
  end

  test "a body without images, or a missing node, attaches nothing" do
    stub_body("<p>No pictures</p>")
    assert_equal 0, fetch

    stub_request(:post, GRAPHQL).to_return(body: { data: { node: nil } }.to_json)
    assert_equal 0, fetch
  end

  test "an entry that already has images is not fetched again" do
    stub_body(img(SIGNED))
    stub_image(SIGNED)
    assert_equal 1, fetch
    assert_equal 0, fetch
    assert_requested :post, GRAPHQL, times: 1
  end

  test "an approved entry is never touched" do
    @entry.update_columns(status: "approved", approved_at: Time.current, released_on: Date.current)
    assert_equal 0, fetch
    assert_not_requested :post, GRAPHQL
  end

  test "roadmap entries and subjects without a node id are skipped" do
    assert_equal 0, Shiplog::ImageFetcher.call(shiplog_entries(:soon_item_roadmap))
    commit_entry = shiplog_entries(:typo_change_discarded)
    commit_entry.update_columns(status: "draft")
    assert_equal 0, Shiplog::ImageFetcher.call(commit_entry)
    assert_not_requested :post, GRAPHQL
  end

  test "nothing is fetched with config.images = false or max_images_per_entry = 0" do
    Shiplog.config.images = false
    assert_equal 0, fetch
    Shiplog.config.images = true
    Shiplog.config.max_images_per_entry = 0
    assert_equal 0, fetch
    assert_not_requested :post, GRAPHQL
  end

  test "nothing is fetched without Active Storage" do
    without_active_storage { assert_equal 0, fetch }
    assert_not_requested :post, GRAPHQL
  end
end
