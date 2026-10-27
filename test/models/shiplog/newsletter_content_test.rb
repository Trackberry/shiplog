require "test_helper"

# The newsletter's highlights (feature cards) and the split rule of Shiplog::Newsletter::Content.
class Shiplog::NewsletterContentTest < ActiveSupport::TestCase
  STRUCTURED = "Intro sentence here.\n\n## Highlights\n\n### Dark mode\n\nBody text.\n\n## Also improved\n\n### Billing\n\n- Tax breakdown.".freeze

  setup do
    enable_newsletter!
    @entry = approved_announcement
    @entry.update!(title: "October recap", body: STRUCTURED)
    @dark_mode = shiplog_entries(:dark_mode_feature)
  end

  def feature!(title, body, slug:, released_on: Date.new(2026, 10, 12), kind: "feature")
    issue = Shiplog::Issue.create!(repository: shiplog_repositories(:app), node_id: SecureRandom.hex(8), number: rand(10_000), title:, url: "https://example.com/i")
    Shiplog::Entry.create!(kind:, status: "approved", subject: issue, title:, body:, slug:, released_on:, approved_at: Time.current)
  end

  def attach_png!(entry, width: nil, height: nil, alt: nil)
    image, = entry.add_images([ { io: StringIO.new(image_bytes(:png)), filename: "shot.png", content_type: "image/png" } ])
    image.blob.update!(metadata: image.blob.metadata.merge(width:, height:).compact)
    entry.update_image_alt(image.blob_id, alt) if alt
    image
  end

  def content(locale = "en") = Shiplog::Newsletter::Content.new(@entry, locale)

  test "highlights are the month's features with a permalink, in the changelog's order, three at most" do
    feature!("Faster imports", "Imports are faster now. Really.", slug: "faster-imports", released_on: Date.new(2026, 10, 15))
    feature!("No page", "Nothing links here.", slug: nil, released_on: Date.new(2026, 10, 2))
    feature!("A change", "Not a feature.", slug: "a-change", kind: "change")
    feature!("Fourth", "Fourth feature.", slug: "fourth", released_on: Date.new(2026, 10, 30))
    feature!("Fifth", "Fifth feature.", slug: "fifth", released_on: Date.new(2026, 10, 31))

    highlights = content.highlights

    assert_equal [ "Dark mode", "Faster imports", "Fourth" ], highlights.map(&:title)
    assert_equal [ "https://example.com/changelog/dark-mode", "https://example.com/changelog/faster-imports", "https://example.com/changelog/fourth" ], highlights.map(&:url)
    assert_equal "Switch to a dark theme.", highlights.first.summary
    assert_equal "Imports are faster now.", highlights[1].summary
    assert highlights.none?(&:image?)
    assert_nil highlights.first.image_url
  end

  test "the summary is the first sentence of the feature's body, cut at 180 characters" do
    @dark_mode.update!(body: "#{"word " * 50}end of a long first sentence! Second sentence.")

    summary = content.highlights.first.summary
    assert_operator summary.length, :<=, 180
    assert summary.end_with?("...")

    @dark_mode.update!(body: "No punctuation at all")
    assert_equal "No punctuation at all", Shiplog::Newsletter::Content.new(@entry, "en").highlights.first.summary
    @dark_mode.update!(body: "")
    assert_equal "", Shiplog::Newsletter::Content.new(@entry, "en").highlights.first.summary
  end

  test "highlights use the features' translations in the locale" do
    Shiplog.config.locales = [ :es ]
    @dark_mode.translations.create!(locale: "es", title: "Modo oscuro", body: "Cambia a un tema oscuro. Más cómodo.", source_digest: @dark_mode.translation_source_digest)

    spanish = content("es").highlights.first
    assert_equal "Modo oscuro", spanish.title
    assert_equal "Cambia a un tema oscuro.", spanish.summary
    assert_equal "Dark mode", content("en").highlights.first.title
    assert_equal "Dark mode", content("fr").highlights.first.title, "an unconfigured locale gets English"
  end

  test "the first screenshot becomes an absolute URL through Active Storage's redirect route, with its size and alt text" do
    attach_png!(@dark_mode, width: 1200, height: 700, alt: "The dark theme")
    second = attach_png!(@dark_mode)

    highlight = content.highlights.first

    assert highlight.image?
    assert_match %r{\Ahttps://example\.com/rails/active_storage/blobs/redirect/[A-Za-z0-9_=-]+--[a-f0-9]+/shot\.png\z}, highlight.image_url
    assert_not_includes highlight.image_url, second.blob.signed_id
    assert_equal 1200, highlight.image_width
    assert_equal 700, highlight.image_height
    assert_equal "The dark theme", highlight.image_alt
  end

  test "a screenshot without analysed size, or without a custom alt text, still works" do
    attach_png!(@dark_mode)

    highlight = content.highlights.first

    assert highlight.image?
    assert_nil highlight.image_width
    assert_nil highlight.image_height
    assert_equal "Dark mode", highlight.image_alt
  end

  test "a screenshot whose URL cannot be built is left out, with a log line that names the entry only" do
    attach_png!(@dark_mode)
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    failing = ->(_attachment) { raise ActionController::UrlGenerationError, "no route for example@example.com" }

    highlight = with_stub(Shiplog::Newsletter::Content, :image_url, failing) { content.highlights.first }

    assert_not highlight.image?
    assert_equal "Dark mode", highlight.title
    assert_match(/the screenshot of entry #{@dark_mode.id} is left out: ActionController::UrlGenerationError/, log.string)
    assert_not_includes log.string, "example@example.com"
  ensure
    Rails.logger = original
  end

  test "screenshots are left out while images are off" do
    attach_png!(@dark_mode)
    Shiplog.config.images = false

    assert_not content.highlights.first.image?
  end

  test "highlights are built once per Content and need no subject other than a period" do
    subject = Shiplog::Entry.find(@entry.id)
    first = Shiplog::Newsletter::Content.new(subject, "en")
    assert_same first.highlights, first.highlights

    feature = Shiplog::Entry.new(kind: "announcement", subject: @dark_mode.subject, title: "x", body: "y")
    assert_empty Shiplog::Newsletter::Content.new(feature, "en").highlights
  end

  test "with highlights and two sections, the email shows the intro, the cards and the rest" do
    subject = content

    assert subject.highlights_shown?
    assert_includes subject.intro_html, "Intro sentence here."
    assert_not_includes subject.intro_html, "Highlights"
    assert_includes subject.rest_html, "Also improved"
    assert_includes subject.rest_html, "Billing"
    assert_includes subject.rest_html, "Tax breakdown."
    assert_not_includes subject.rest_html, "Dark mode"
    assert_equal "Intro sentence here.", subject.intro_text
    assert_equal "Also improved\n\nBilling\n\n- Tax breakdown.", subject.rest_text
    assert_equal "Intro sentence here.", subject.preheader
    assert_includes subject.html, "Highlights", "the whole body stays available"
  end

  test "the split rule works on a translation, whatever its headings say" do
    Shiplog.config.locales = [ :es ]
    @entry.translations.create!(locale: "es", title: "Resumen", body: "Introducción.\n\n## Destacados\n\n### Modo oscuro\n\nTexto.\n\n## También mejoramos\n\n- Impuestos.",
      source_digest: @entry.translation_source_digest)

    spanish = content("es")

    assert spanish.highlights_shown?
    assert_equal "Introducción.", spanish.intro_text
    assert_equal "También mejoramos\n\n- Impuestos.", spanish.rest_text
  end

  test "a body without an intro, or with headings indented or carriage returns, still splits" do
    @entry.update!(body: "## Highlights\r\n\r\nText.\r\n\r\n   ## Also improved\r\n\r\n- One.")

    subject = content
    assert subject.highlights_shown?
    assert_nil subject.intro_html.presence
    assert_equal "Also improved\n\n- One.", subject.rest_text
  end

  test "without highlights, or with fewer than two sections, the body is shown whole" do
    @dark_mode.update_columns(slug: nil)
    subject = content
    assert_empty subject.highlights
    assert_not subject.highlights_shown?
    assert_nil subject.intro_html
    assert_nil subject.rest_html
    assert_nil subject.intro_text
    assert_equal "Intro sentence here.", subject.preheader

    @dark_mode.update_columns(slug: "dark-mode")
    @entry.update!(body: "Intro.\n\n## Only one section\n\n- a")
    subject = content
    assert_equal 1, subject.highlights.size
    assert_not subject.highlights_shown?

    @entry.update!(body: "No headings at all.")
    assert_not content.highlights_shown?
  end

  test "highlights can be given, for the preview" do
    given = [ Shiplog::Newsletter::Content::Highlight.new(title: "T", summary: "S", url: "https://example.com/t", image_url: nil, image_alt: nil, image_width: nil, image_height: nil) ]

    subject = Shiplog::Newsletter::Content.new(@entry, "en", highlights: given)

    assert_equal given, subject.highlights
    assert subject.highlights_shown?
    assert_not Shiplog::Newsletter::Content.new(@entry, "en", highlights: []).highlights_shown?
  end
end
