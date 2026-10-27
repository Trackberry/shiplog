module Shiplog
  module Newsletter
    # What a newsletter says in one locale: the announcement's title, subject and body (the current translation,
    # English when there is none), the Markdown rendered once as inline-styled HTML and as plain text, the
    # month's feature highlights (cards with a screenshot, a sentence and a link), and the links.
    # SendNewsletterJob builds one per locale and hands it to every message of that locale.
    #
    # The split rule: when there are highlights and the body has at least two "## " sections, the email shows
    # the intro (the text before the first heading), the highlight cards in place of the body's FIRST section,
    # then the rest of the body from the second section on ("Also improved"). Otherwise the body is shown whole.
    # The split is made on the Markdown of the locale's text, so it works for translations whatever the headings
    # say. Card texts come from the features' own approved (translated) entries, not from the body.
    class Content
      MAX_HIGHLIGHTS = 3
      SUMMARY_LENGTH = 180
      PREHEADER_LENGTH = 150
      # A "## " heading at the start of a line (Markdown allows up to three leading spaces).
      SECTION = /^ {0,3}\#{2}[ \t]/

      # One highlight card: a feature's title, first sentence and permalink, and its first screenshot (absolute
      # URL, alt text, size when the blob was analysed) or nil without one.
      Highlight = Data.define(:title, :summary, :url, :image_url, :image_alt, :image_width, :image_height) do
        def image? = image_url.present?
      end

      # The inline styles of the body's tags in the HTML part (email clients ignore stylesheets; see Markdown).
      BODY_STYLES = {
        "h1" => "margin:28px 0 10px;font-size:20px;line-height:1.3;font-weight:700;color:#1f2328;",
        "h2" => "margin:28px 0 10px;font-size:18px;line-height:1.3;font-weight:700;color:#1f2328;",
        "h3" => "margin:20px 0 6px;font-size:15px;line-height:1.4;font-weight:600;color:#1f2328;",
        "h4" => "margin:16px 0 4px;font-size:15px;line-height:1.4;font-weight:600;color:#1f2328;",
        "h5" => "margin:16px 0 4px;font-size:15px;line-height:1.4;font-weight:600;color:#1f2328;",
        "h6" => "margin:16px 0 4px;font-size:15px;line-height:1.4;font-weight:600;color:#1f2328;",
        "p" => "margin:0 0 12px;font-size:16px;line-height:1.6;color:#1f2328;",
        "ul" => "margin:0 0 12px;padding:0 0 0 20px;",
        "ol" => "margin:0 0 12px;padding:0 0 0 20px;",
        "li" => "margin:0 0 4px;font-size:15px;line-height:1.55;color:#1f2328;",
        "blockquote" => "margin:0 0 12px;padding:0 0 0 12px;border-left:3px solid #d1d9e0;color:#59636e;",
        "hr" => "border:0;border-top:1px solid #d1d9e0;margin:20px 0;",
        "code" => "font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:14px;background-color:#f6f8fa;padding:1px 4px;border-radius:3px;",
        "img" => "display:block;max-width:100%;height:auto;border-radius:8px;margin:0 0 12px;"
      }.freeze

      attr_reader :entry, :locale

      # `highlights:` replaces the ones built from the month's features (the mailer preview, with no rows).
      def initialize(entry, locale, highlights: nil)
        @entry = entry
        @locale = Newsletter.locale_for(locale)
        @highlights = highlights
      end

      def title = entry.display_title(locale).to_s

      def subject = title

      # The month the announcement covers ("October 2026"), in the locale when its I18n data has month names.
      def month = Period.month_name(entry.released_on || Date.current, locale: Newsletter.i18n_locale(locale))

      # The whole body as HTML, each tag inline-styled, links in the accent colour. Rendered once per Content.
      def html = @html ||= render_html(markdown)

      def text = @text ||= entry.to_text(locale)

      # The body's first line, cut short, for the preheader (the preview line next to the subject).
      def preheader = (intro_text.presence || text).lines.first.to_s.squish.truncate(PREHEADER_LENGTH)

      # Up to MAX_HIGHLIGHTS of the month's approved features, in the changelog's order, each with a permalink
      # (features without one are skipped). Built once per Content.
      def highlights
        @highlights ||= features.lazy.filter_map { |feature| highlight(feature) }.first(MAX_HIGHLIGHTS)
      end

      # Whether the email shows the intro, the cards and the rest instead of the whole body (the split rule).
      def highlights_shown? = highlights.any? && sections.size >= 2

      # The text before the body's first "## " heading, as HTML; nil unless the split rule applies.
      def intro_html
        @intro_html ||= render_html(intro_markdown) if highlights_shown?
      end

      # The body from its second "## " heading on, as HTML; nil unless the split rule applies. It opens a card, whose
      # padding already spaces it, so the opening heading's top margin is dropped.
      def rest_html
        @rest_html ||= flush_top(render_html(rest_markdown)) if highlights_shown?
      end

      def intro_text
        @intro_text ||= Markdown.to_text(intro_markdown) if highlights_shown?
      end

      def rest_text
        @rest_text ||= Markdown.to_text(rest_markdown) if highlights_shown?
      end

      def view_url = @view_url ||= Newsletter.announcement_url(entry, locale)

      def changelog_url = @changelog_url ||= Newsletter.changelog_url

      def accent = Shiplog.config.newsletter_accent || "#0969da"

      def logo_url = Shiplog.config.newsletter_logo_url

      def address = Shiplog.config.newsletter_address

      def product_name = Newsletter.product_name

      # The absolute URL of an attachment's file through Active Storage's redirect route (the host's), or nil.
      def self.image_url(attachment)
        path = Rails.application.routes.url_helpers.rails_blob_path(attachment.blob, only_path: true)
        Newsletter.absolute_url(path)
      end

      private

      def markdown = @markdown ||= entry.to_markdown(locale).gsub(/\r\n?/, "\n")

      # The body cut at its "## " headings: the text before the first one, then one String per section.
      def sections = @sections ||= markdown.split(/(?=#{SECTION.source})/).tap { |parts| parts.shift unless parts.first.to_s.match?(SECTION) }

      def intro_markdown = markdown.match?(SECTION) ? markdown.split(SECTION, 2).first.to_s : markdown

      def rest_markdown = sections.drop(1).join

      # The HTML with the top margin of a leading heading set to 0 (its style is BODY_STYLES', so it starts "margin:").
      def flush_top(html)
        html.sub(/\A(\s*<h[1-6] style=")margin:\d+px/) { "#{Regexp.last_match(1)}margin:0" }.html_safe # rubocop:disable Rails/OutputSafety
      end

      def render_html(source) = Markdown.to_html(source, styles: BODY_STYLES.merge("a" => "color:#{accent};text-decoration:underline;"))

      # The month's approved features, images and this locale's translations loaded at once.
      def features
        period = entry.subject
        return [] unless period.is_a?(Period)

        features = period.changelog_entries.with_images_loaded.to_a.select(&:feature?)
        Entry.preload_translations(features, locale:)
        features
      end

      def highlight(feature)
        url = Newsletter.absolute_url(PublicLinks.entry_url(feature))
        return unless url

        image = Shiplog.images? ? feature.ordered_images.first : nil
        image_url = image && screenshot_url(feature, image)
        metadata = image_url ? image.blob.metadata : {}
        feature_title = feature.display_title(locale).to_s
        Highlight.new(title: feature_title, summary: first_sentence(feature.display_body(locale)), url:, image_url:,
          image_alt: (image_url ? feature.custom_image_alt(image) || feature_title : nil),
          image_width: metadata[:width].to_i.positive? ? metadata[:width].to_i : nil,
          image_height: metadata[:height].to_i.positive? ? metadata[:height].to_i : nil)
      end

      # A screenshot's absolute URL; nil, after a log line (no address in it), when the host's routes cannot give one.
      def screenshot_url(feature, image)
        self.class.image_url(image)
      rescue StandardError => error
        Rails.logger.warn("[shiplog] Newsletter: the screenshot of entry #{feature.id} is left out: #{error.class}")
        nil
      end

      # The first sentence of a plain-text body (punctuation kept), cut at SUMMARY_LENGTH.
      def first_sentence(body)
        text = body.to_s.squish
        match = text.match(Rewriter::SENTENCE_END)
        (match ? text[0...match.end(0)] : text).truncate(SUMMARY_LENGTH)
      end
    end
  end
end
