module Shiplog
  module Newsletter
    # What a newsletter says in one locale: the announcement's title, subject and body (the current translation,
    # English when there is none), the Markdown rendered once as inline-styled HTML and as plain text, and the
    # links. SendNewsletterJob builds one per locale and hands it to every message of that locale.
    class Content
      # The inline styles of the body's tags in the HTML part (email clients ignore stylesheets; see Markdown).
      BODY_STYLES = {
        "h1" => "margin:24px 0 8px;font-size:20px;line-height:1.3;font-weight:600;color:#1f2328;",
        "h2" => "margin:24px 0 8px;font-size:18px;line-height:1.3;font-weight:600;color:#1f2328;",
        "h3" => "margin:20px 0 6px;font-size:16px;line-height:1.3;font-weight:600;color:#1f2328;",
        "h4" => "margin:16px 0 4px;font-size:15px;line-height:1.3;font-weight:600;color:#1f2328;",
        "h5" => "margin:16px 0 4px;font-size:15px;line-height:1.3;font-weight:600;color:#1f2328;",
        "h6" => "margin:16px 0 4px;font-size:15px;line-height:1.3;font-weight:600;color:#1f2328;",
        "p" => "margin:0 0 12px;font-size:16px;line-height:1.6;color:#1f2328;",
        "ul" => "margin:0 0 12px;padding:0 0 0 24px;",
        "ol" => "margin:0 0 12px;padding:0 0 0 24px;",
        "li" => "margin:0 0 6px;font-size:16px;line-height:1.6;color:#1f2328;",
        "blockquote" => "margin:0 0 12px;padding:0 0 0 12px;border-left:3px solid #d1d9e0;color:#59636e;",
        "hr" => "border:0;border-top:1px solid #d1d9e0;margin:20px 0;",
        "code" => "font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:14px;background-color:#f6f8fa;padding:1px 4px;border-radius:3px;",
        "img" => "display:block;max-width:100%;height:auto;border-radius:6px;margin:0 0 12px;"
      }.freeze

      attr_reader :entry, :locale

      def initialize(entry, locale)
        @entry = entry
        @locale = Newsletter.locale_for(locale)
      end

      def title = entry.display_title(locale).to_s

      def subject = title

      # The month the announcement covers ("October 2026"), in the locale when its I18n data has month names.
      def month = Period.month_name(entry.released_on || Date.current, locale: Newsletter.i18n_locale(locale))

      # The body as HTML, each tag inline-styled, links in the accent colour. Rendered once per Content.
      def html
        @html ||= Markdown.to_html(entry.to_markdown(locale), styles: BODY_STYLES.merge("a" => "color:#{accent};text-decoration:underline;"))
      end

      def text = @text ||= entry.to_text(locale)

      # The body's first line, cut short, for the preheader (the preview line next to the subject).
      def preheader = text.lines.first.to_s.squish.truncate(PREHEADER_LENGTH)
      PREHEADER_LENGTH = 150

      def view_url = @view_url ||= Newsletter.announcement_url(entry, locale)

      def changelog_url = @changelog_url ||= Newsletter.changelog_url

      def accent = Shiplog.config.newsletter_accent || "#0969da"

      def logo_url = Shiplog.config.newsletter_logo_url

      def address = Shiplog.config.newsletter_address

      def product_name = Newsletter.product_name
    end
  end
end
