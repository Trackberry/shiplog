require "test_helper"

# shiplog_head_tags: one helper call in a host layout renders the description, canonical, robots, Open Graph,
# Twitter, feed and structured-data tags of the public pages.
class Shiplog::HeadTagsTest < ActionDispatch::IntegrationTest
  OVERRIDES = Rails.root.join("../fixtures/files/views/head_override").freeze

  setup do
    Shiplog.config.public_layout = "head_helper"
    @dark = shiplog_entries(:dark_mode_feature)
  end

  def metas(attribute, prefix) = css_select("head meta[#{attribute}^='#{prefix}']").map { |meta| [ meta[attribute], meta["content"] ] }
  def og = metas("property", "og:")
  def twitter = metas("name", "twitter:")
  def meta_content(attribute, value) = css_select("head meta[#{attribute}='#{value}']").map { |meta| meta["content"] }
  def canonicals = css_select("head link[rel=canonical]").map { |link| link["href"] }
  def feeds = css_select("head link[rel=alternate][type='application/atom+xml']")
  def json_ld = css_select("head script[type='application/ld+json']")

  def assert_unique(pairs)
    assert_equal pairs.map(&:first).uniq, pairs.map(&:first), "a tag is emitted twice: #{pairs.inspect}"
  end

  def publish_with_png(entry = @dark)
    entry.add_images([ { io: StringIO.new(image_bytes(:png)), filename: "first.png", content_type: "image/png" } ])
  end

  test "the permalink page has the full tag set, each key once" do
    get "/changelog/dark-mode"

    assert_equal [ "Switch to a dark theme." ], meta_content("name", "description")
    assert_equal [ "http://www.example.com/changelog/dark-mode" ], canonicals
    assert_empty meta_content("name", "robots")
    assert_equal({ "og:title" => "Dark mode", "og:description" => "Switch to a dark theme.", "og:type" => "article",
      "og:url" => "http://www.example.com/changelog/dark-mode" }, og.to_h)
    assert_unique og
    assert_equal({ "twitter:card" => "summary" }, twitter.to_h)
    assert_unique twitter
    assert_equal [ "http://www.example.com/changelog.atom" ], feeds.map { |link| link["href"] }
    assert_equal 1, json_ld.size
    assert_equal "Article", JSON.parse(json_ld.first.text)["@type"]
  end

  test "the changelog list has the full tag set and a canonical without the query string" do
    get "/changelog", params: { utm_source: "x" }

    assert_equal [ "http://www.example.com/changelog" ], canonicals
    assert_empty meta_content("name", "description")
    assert_empty meta_content("name", "robots")
    assert_equal({ "og:title" => "Changelog", "og:type" => "website", "og:url" => "http://www.example.com/changelog" }, og.to_h)
    assert_unique og
    assert_equal({ "twitter:card" => "summary" }, twitter.to_h)
    assert_equal 1, feeds.size
    assert_equal "CollectionPage", JSON.parse(json_ld.first.text)["@type"]
    assert_empty css_select("head meta[property='og:image']")
  end

  test "the roadmap has the full tag set and no feed" do
    get "/roadmap"

    assert_equal [ "http://www.example.com/roadmap" ], canonicals
    assert_equal({ "og:title" => "Roadmap", "og:type" => "website", "og:url" => "http://www.example.com/roadmap" }, og.to_h)
    assert_unique og
    assert_equal({ "twitter:card" => "summary" }, twitter.to_h)
    assert_empty feeds
    assert_equal 1, json_ld.size
    assert_empty meta_content("name", "robots")
  end

  test "a search page is noindex and has no canonical" do
    get "/changelog", params: { q: "dark" }

    assert_equal [ "noindex" ], meta_content("name", "robots")
    assert_empty canonicals
    assert_empty css_select("head meta[property='og:url']")
    assert_equal [ "Changelog" ], meta_content("property", "og:title")
    assert_equal 1, feeds.size
    assert_empty json_ld
  end

  test "a canonical_url is honoured by the canonical link, og:url and the feed" do
    Shiplog.config.canonical_url = "https://example.com"
    get "/changelog/dark-mode"

    assert_equal [ "https://example.com/changelog/dark-mode" ], canonicals
    assert_equal [ "https://example.com/changelog/dark-mode" ], meta_content("property", "og:url")
    assert_equal [ "https://example.com/changelog.atom" ], feeds.map { |link| link["href"] }
  end

  test "except canonical drops the link only: og:url keeps Shiplog's canonical, which honours canonical_url" do
    Shiplog.config.public_layout = "head_canonical_host"
    Shiplog.config.canonical_url = "https://example.com"
    get "/changelog/dark-mode"

    assert_empty canonicals
    assert_equal [ "https://example.com/changelog/dark-mode" ], meta_content("property", "og:url")
  end

  test "on a search page content_for(:shiplog_robots) is noindex, for a host that writes its own canonical" do
    Shiplog.config.public_layout = "head_canonical_host"
    get "/changelog", params: { q: "dark" }
    assert_equal [ "noindex" ], meta_content("name", "probe-robots")

    get "/changelog"
    assert_empty meta_content("name", "probe-robots")
  end

  test "except removes only its own tags" do
    {
      description: -> { meta_content("name", "description") },
      canonical: -> { canonicals },
      open_graph: -> { og },
      twitter: -> { twitter },
      feed: -> { feeds },
      structured_data: -> { json_ld }
    }.each do |key, reader|
      get "/changelog/dark-mode", params: { except: [ key ] }
      assert_empty reader.call, "#{key} should be gone"
      others = { description: meta_content("name", "description"), canonical: canonicals, open_graph: og, twitter:, feed: feeds, structured_data: json_ld }.except(key)
      assert others.values.none?(&:empty?), "except #{key} removed more than its own tags: #{others.select { |_, v| v.empty? }.keys}"
    end
  end

  test "except robots removes the noindex" do
    get "/changelog", params: { q: "dark", except: [ "robots" ] }
    assert_empty meta_content("name", "robots")
    assert_equal 1, feeds.size
  end

  test "an unknown except key raises" do
    error = assert_raises(ActionView::Template::Error) { get "/changelog", params: { except: [ "title" ] } }
    assert_kind_of ArgumentError, error.cause
    assert_match(/Unknown shiplog_head_tags except: key.*:title/, error.message)
  end

  test "it is empty on a host page" do
    get "/news"
    assert_response :ok
    assert_empty css_select("head link[rel=canonical], head meta[property^='og:'], head meta[name^=twitter], head script[type='application/ld+json']")
  end

  test "it is empty in a view that lacks the engine's helper, such as a component, even under a Shiplog controller" do
    controller = Shiplog::PublicController.new
    component_class = Class.new(ActionView::Base)
    view = component_class.with_empty_template_cache.new(ActionView::LookupContext.new([]), {}, controller)

    assert_not view.respond_to?(:shiplog_render_head_tags, true)
    assert_equal "", view.shiplog_head_tags
  end

  test "the public controllers carry the marker that shiplog_head_tags checks, and host controllers don't" do
    assert Shiplog::PublicController.new.respond_to?(:shiplog_public_page?)
    assert_not ApplicationController.new.respond_to?(:shiplog_public_page?)
  end

  test "the constant of shiplog_head_tags does not leak into the host's views" do
    assert_not ActionView::Base.const_defined?(:EXCEPT_KEYS)
    assert_not Shiplog::HeadTagsHelper.const_defined?(:EXCEPT_KEYS)
    assert_includes Shiplog::HeadTags::EXCEPT_KEYS, :canonical
  end

  test "it validates its keys on a host page too" do
    assert_raises(ArgumentError) { ApplicationController.new.view_context.shiplog_head_tags(except: [ :nope ]) }
  end

  test "a partial in the host app overrides the engine's" do
    original = Shiplog::PublicController.view_paths
    Shiplog::PublicController.prepend_view_path(OVERRIDES.to_s)
    get "/changelog/dark-mode"

    assert_equal [ "HOST OVERRIDE Dark mode" ], meta_content("property", "og:title")
    assert_equal [ "http://www.example.com/changelog/dark-mode" ], canonicals, "the other partials are untouched"
  ensure
    Shiplog::PublicController.view_paths = original
  end

  test "Spanish pages carry the translated tags" do
    Shiplog.config.locales = [ :es ]
    @dark.translations.create!(locale: "es", title: "Modo oscuro", body: "Cambia a un tema oscuro.", source_digest: @dark.translation_source_digest)
    I18n.with_locale(:es) { get "/changelog/dark-mode" }

    assert_equal [ "Cambia a un tema oscuro." ], meta_content("name", "description")
    assert_equal [ "Modo oscuro" ], meta_content("property", "og:title")
    assert_equal [ "Cambia a un tema oscuro." ], meta_content("property", "og:description")
    assert_equal "es", JSON.parse(json_ld.first.text)["inLanguage"]
    assert_equal "Modo oscuro", JSON.parse(json_ld.first.text)["headline"]
  end

  test "titles with quotes and a script end tag are escaped in every tag" do
    @dark.update!(title: %(Say "hi" </script><b>), body: %(He said "no" </script> & more))
    get "/changelog/dark-mode"

    assert_equal [ %(Say "hi" </script><b>) ], meta_content("property", "og:title")
    assert_equal [ %(He said "no" </script> & more) ], meta_content("name", "description")
    assert_equal 1, json_ld.size
    assert_equal 1, response.body.scan("<script type=\"application/ld+json\">").size
    assert_no_match(%r{</script><b>}, response.body)
    assert_equal %(Say "hi" </script><b>), JSON.parse(json_ld.first.text)["headline"]
  end

  # The Open Graph image.

  test "the first screenshot is the og:image, with alt, the large Twitter card and the JSON-LD image" do
    Shiplog.config.og_image = ->(_entry, _locale) { "https://cdn.example.com/card.png" }
    publish_with_png
    get "/changelog/dark-mode"

    image = meta_content("property", "og:image")
    assert_equal 1, image.size
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/blobs/redirect/.+/first\.png\z}, image.first
    assert_equal [ "Dark mode" ], meta_content("property", "og:image:alt")
    assert_equal [ "summary_large_image" ], meta_content("name", "twitter:card")
    assert_equal image, meta_content("name", "twitter:image")
    assert_equal [ image.first ], JSON.parse(json_ld.first.text)["image"]
    assert_unique og
    assert_unique twitter
  end

  test "a first screenshot whose URL does not resolve is skipped by the og:image, like the JSON-LD image" do
    Shiplog.config.og_image = ->(_entry, _locale) { "https://cdn.example.com/card.png" }
    @dark.add_images([ { io: StringIO.new(image_bytes(:png)), filename: "broken.png", content_type: "image/png" },
                       { io: StringIO.new(image_bytes(:png)), filename: "second.png", content_type: "image/png" } ])
    unresolvable = Module.new do
      def shiplog_image_url(image) = (super unless image.filename.to_s == "broken.png")
    end
    Shiplog::PermalinkHelper.prepend(unresolvable)
    get "/changelog/dark-mode"

    image = meta_content("property", "og:image")
    assert_equal 1, image.size
    assert_match %r{/second\.png\z}, image.first
    assert_equal image, JSON.parse(json_ld.first.text)["image"]
  end

  test "config.og_image is used when the entry has no screenshot" do
    seen = nil
    Shiplog.config.og_image = ->(entry, locale) { seen = [ entry, locale ]; "https://cdn.example.com/#{entry.slug}-#{locale}.png" }
    get "/changelog/dark-mode"

    assert_equal [ "https://cdn.example.com/dark-mode-en.png" ], meta_content("property", "og:image")
    assert_equal [ "https://cdn.example.com/dark-mode-en.png" ], meta_content("name", "twitter:image")
    assert_equal [ "Dark mode" ], meta_content("property", "og:image:alt")
    assert_equal [ "summary_large_image" ], meta_content("name", "twitter:card")
    assert_equal [ "https://cdn.example.com/dark-mode-en.png" ], JSON.parse(json_ld.first.text)["image"]
    assert_equal [ @dark, :en ], seen
  end

  test "config.og_image is evaluated in the view, so route helpers work" do
    Shiplog.config.og_image = ->(_entry, _locale) { main_app.about_url }
    get "/changelog/dark-mode"
    assert_equal [ "http://www.example.com/about" ], meta_content("property", "og:image")
  end

  test "a path from config.og_image is made absolute with the request's origin or the canonical_url" do
    Shiplog.config.og_image = ->(_entry, _locale) { "/cards/dark.png" }
    get "/changelog/dark-mode"
    assert_equal [ "http://www.example.com/cards/dark.png" ], meta_content("property", "og:image")

    Shiplog.config.canonical_url = "https://example.com"
    get "/changelog/dark-mode"
    assert_equal [ "https://example.com/cards/dark.png" ], meta_content("property", "og:image")
    assert_equal [ "https://example.com/cards/dark.png" ], JSON.parse(json_ld.first.text)["image"]
  end

  test "without a screenshot or a callable there is no image and the card is a summary" do
    get "/changelog/dark-mode"
    assert_empty css_select("head meta[property^='og:image']")
    assert_empty meta_content("name", "twitter:image")
    assert_equal [ "summary" ], meta_content("name", "twitter:card")
    assert_nil JSON.parse(json_ld.first.text)["image"]
  end

  test "a callable that raises is logged once and the page renders without the image" do
    Shiplog.config.og_image = ->(_entry, _locale) { raise "boom" }
    logged = capture_log { get "/changelog/dark-mode" }

    assert_response :ok
    assert_empty css_select("head meta[property^='og:image']")
    assert_equal [ "summary" ], meta_content("name", "twitter:card")
    assert_nil JSON.parse(json_ld.first.text)["image"]
    assert_equal 1, logged.scan("[shiplog] config.og_image").size
    assert_includes logged, "boom"
  end

  test "a callable that returns a javascript: value is logged and ignored" do
    Shiplog.config.og_image = ->(_entry, _locale) { "javascript:alert(1)" }
    logged = capture_log { get "/changelog/dark-mode" }

    assert_response :ok
    assert_empty css_select("head meta[property^='og:image']")
    assert_equal 1, logged.scan("[shiplog] config.og_image").size
    assert_no_match(/javascript/, response.body)
  end

  test "a callable that returns nil or a protocol-relative URL gets no image" do
    [ nil, "//evil.example/x.png", 42 ].each do |value|
      Shiplog.config.og_image = ->(_entry, _locale) { value }
      capture_log { get "/changelog/dark-mode" }
      assert_empty css_select("head meta[property^='og:image']"), value.inspect
    end
  end

  test "list pages and the roadmap get no image from config.og_image" do
    Shiplog.config.og_image = ->(_entry, _locale) { "https://cdn.example.com/card.png" }
    get "/changelog"
    assert_empty css_select("head meta[property^='og:image']")
    get "/roadmap"
    assert_empty css_select("head meta[property^='og:image']")
  end

  # Old layouts and the migration to the helper.

  test "the legacy content_for blocks alone still produce what they did in 0.3.0 while config.og_image is unset" do
    Shiplog.config.public_layout = "head_legacy"
    get "/changelog/dark-mode"

    assert_equal [ "Switch to a dark theme." ], meta_content("name", "description")
    assert_equal({ "og:title" => "Dark mode", "og:description" => "Switch to a dark theme.", "og:type" => "article",
      "og:url" => "http://www.example.com/changelog/dark-mode" }, og.to_h)
    assert_unique og
    assert_equal 1, feeds.size
    assert_equal 1, json_ld.size
    assert_empty canonicals
    assert_empty twitter
  end

  test "the legacy :shiplog_og block includes the config.og_image fallback image" do
    Shiplog.config.public_layout = "head_legacy"
    Shiplog.config.og_image = ->(_entry, _locale) { "https://cdn.example.com/card.png" }
    get "/changelog/dark-mode"

    assert_equal [ "https://cdn.example.com/card.png" ], meta_content("property", "og:image")
    assert_unique og
  end

  test "shiplog_head_tags alone yields exactly one of each tag, and never reads the legacy blocks" do
    Shiplog.config.og_image = ->(_entry, _locale) { "https://cdn.example.com/card.png" }
    get "/changelog/dark-mode"

    assert_unique og
    assert_unique twitter
    assert_equal 1, css_select("head meta[name=description]").size
    assert_equal 1, canonicals.size
    assert_equal 1, feeds.size
    assert_equal 1, json_ld.size
    assert_equal 1, css_select("head meta[property='og:image']").size
  end

  test "a layout that renders both the blocks and the helper duplicates the tags, which is why you use one" do
    Shiplog.config.public_layout = "head_both"
    get "/changelog/dark-mode"
    assert_equal 2, css_select("head meta[name=description]").size
  end

  test "a host controller without the helper renders a layout calling shiplog_head_tags, with no Shiplog tags" do
    get "/plain"
    assert_response :ok
    assert_empty css_select("head link[rel=canonical], head meta[property^='og:'], head meta[name^=twitter], head script[type='application/ld+json']")
    assert_select "#plain-page"
  end

  test "only shiplog_head_tags is added to every view" do
    assert_includes ActionView::Base.instance_method(:shiplog_head_tags).owner.name, "HeadTagsHelper"
    assert_not ActionView::Base.method_defined?(:shiplog_head_page)
    assert_not ActionView::Base.method_defined?(:shiplog_entry_og_image)
    assert_equal [ :shiplog_head_tags ], Shiplog::HeadTagsHelper.public_instance_methods(false)
  end

  test "the engine's own layout renders everything through the helper" do
    Shiplog.config.public_layout = "shiplog/application"
    get "/changelog/dark-mode"

    assert_equal [ "http://www.example.com/changelog/dark-mode" ], canonicals
    assert_equal [ "summary" ], meta_content("name", "twitter:card")
    assert_unique og
    assert_equal 1, feeds.size
    assert_equal 1, json_ld.size
  end

  private

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end
end
