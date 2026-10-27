module Shiplog
  # The inline styles of the newsletter templates: one place for the palette (light colours that email clients
  # invert sanely in dark mode, no pure black) and the pieces an overriding template can reuse (buttons, cards).
  module NewsletterMailerHelper
    PALETTE = {
      page: "#f3f4f6", card: "#ffffff", text: "#1f2328", muted: "#59636e", border: "#d1d9e0", soft: "#f6f8fa"
    }.freeze
    FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif".freeze
    RADIUS = "10px".freeze

    def shiplog_mail_palette = PALETTE

    def shiplog_mail_font = FONT

    # A button: a one-cell table (Outlook ignores padding on links) with the accent as background. `margin` is the
    # table's CSS margin.
    def shiplog_mail_button(label, url, accent, margin: "24px 0 0")
      return if url.blank?

      tag.table(role: "presentation", cellpadding: "0", cellspacing: "0", border: "0", style: "margin:#{margin};") do
        tag.tr(tag.td(style: "background-color:#{accent};border-radius:6px;") do
          link_to(label, url, style: "display:inline-block;padding:11px 20px;font-family:#{FONT};font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;")
        end)
      end
    end

    # A highlight's screenshot: full width, rounded top corners, sized from the blob's metadata when known.
    def shiplog_mail_screenshot(highlight)
      return unless highlight.image?

      options = { alt: highlight.image_alt, width: 600, border: 0,
        style: "display:block;width:100%;max-width:600px;height:auto;border:0;border-radius:#{RADIUS} #{RADIUS} 0 0;" }
      options[:height] = (600.0 * highlight.image_height / highlight.image_width).round if highlight.image_width.to_i.positive? && highlight.image_height.to_i.positive?
      link_to(image_tag(highlight.image_url, **options), highlight.url, style: "display:block;text-decoration:none;")
    end
  end
end
