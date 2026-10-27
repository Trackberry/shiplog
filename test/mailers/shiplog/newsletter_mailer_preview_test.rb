require "test_helper"
require "action_mailer/preview"
require Shiplog::Engine.root.join("lib/shiplog/previews/shiplog/newsletter_mailer_preview").to_s

# The preview hosts add to action_mailer.preview_paths: it must render with and without an approved announcement.
class Shiplog::NewsletterMailerPreviewTest < ActiveSupport::TestCase
  setup { enable_newsletter! }

  def preview(params = {}) = Shiplog::NewsletterMailerPreview.new(params)

  test "the announcement preview renders a sample when no announcement is approved" do
    mail = preview.announcement

    assert_equal [ "preview@example.com" ], mail.to
    assert_includes mail.html_part.body.to_s, "Dark mode"
    assert_includes mail.html_part.body.to_s, "https://example.com/shiplog/newsletter/unsubscribe/"
    assert_includes mail.html_part.body.to_s, "https://example.com/shiplog/newsletter/preferences/preview-token"
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].to_s
    assert_includes mail.text_part.body.to_s, "Faster imports"
  end

  test "the announcement preview uses the newest approved announcement and the requested locale" do
    Shiplog.config.locales = [ :es ]
    entry = approved_announcement
    entry.update!(title: "October recap")
    entry.translations.create!(locale: "es", title: "Resumen de octubre", body: "Texto", source_digest: entry.translation_source_digest)

    assert_equal "October recap", preview.announcement.subject
    assert_equal "Resumen de octubre", preview("locale" => "es").announcement.subject
  end

  test "the confirmation preview renders" do
    mail = preview.confirmation

    assert_equal [ "preview@example.com" ], mail.to
    assert_includes mail.html_part.body.to_s, "/shiplog/newsletter/confirm/"
  end
end
