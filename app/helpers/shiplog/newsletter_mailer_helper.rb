module Shiplog
  # The inline styles of the newsletter templates: one place for the palette (light colours that email clients
  # invert sanely in dark mode, no pure black) so an overriding template can reuse them.
  module NewsletterMailerHelper
    PALETTE = {
      page: "#f3f4f6", card: "#ffffff", text: "#1f2328", muted: "#59636e", border: "#d1d9e0"
    }.freeze
    FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif".freeze

    def shiplog_mail_palette = PALETTE

    def shiplog_mail_font = FONT

    # A button: a one-cell table (Outlook ignores padding on links) with the accent as background.
    def shiplog_mail_button(label, url, accent)
      return if url.blank?

      tag.table(role: "presentation", cellpadding: "0", cellspacing: "0", border: "0", style: "margin:24px 0 0;") do
        tag.tr(tag.td(style: "background-color:#{accent};border-radius:6px;") do
          link_to(label, url, style: "display:inline-block;padding:11px 20px;font-family:#{FONT};font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;")
        end)
      end
    end
  end
end
