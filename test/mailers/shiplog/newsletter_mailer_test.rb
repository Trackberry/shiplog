require "test_helper"

class Shiplog::NewsletterMailerTest < ActionMailer::TestCase
  BODY = "Intro with [a link](https://example.com/x) and <b>raw</b>.\n\n## Highlights\n\n- Dark mode\n- Faster imports".freeze

  setup do
    enable_newsletter!
    @entry = approved_announcement
    @entry.update!(title: "October recap", body: BODY)
  end

  def announcement(email = "ana@example.com", locale: "en", **options)
    Shiplog::NewsletterMailer.announcement(@entry, email, locale:, unsubscribe_url: "https://example.com/shiplog/newsletter/unsubscribe/TOKEN",
      preferences_url: "https://example.com/shiplog/newsletter/preferences/PREF", **options)
  end

  test "the announcement email has the sender, the subject, both parts and the one-click headers" do
    mail = announcement

    assert_equal [ "ana@example.com" ], mail.to
    assert_equal [ "updates@example.com" ], mail.from
    assert_equal "Acme", mail[:from].display_names.first
    assert_equal "October recap", mail.subject
    assert_equal "<https://example.com/shiplog/newsletter/unsubscribe/TOKEN>", mail["List-Unsubscribe"].to_s
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].to_s
    assert_equal "bulk", mail["Precedence"].to_s
    assert_predicate mail, :multipart?
    assert mail.html_part
    assert mail.text_part
  end

  test "the HTML part is a 600px table with inline styles, the body rendered and escaped, and the footer" do
    Shiplog.config.newsletter_logo_url = "https://example.com/logo.png"
    Shiplog.config.newsletter_accent = "#ff0000"
    Shiplog.config.product_name = "Acme"
    html = announcement.html_part.body.to_s

    assert_includes html, '<table role="presentation" width="600"'
    assert_includes html, %(<meta name="color-scheme" content="light dark">)
    assert_includes html, "October recap"
    assert_includes html, "Monthly update · October 2026"
    logo = html[/<img [^>]*src="https:\/\/example\.com\/logo\.png"[^>]*>/]
    assert logo, "the logo"
    assert_includes logo, %(alt="Acme")
    assert_includes logo, %(width="140")
    assert_includes logo, "max-width:140px"
    assert_includes html, %(<a href="https://example.com/x" style="color:#ff0000;text-decoration:underline;">a link</a>)
    assert_includes html, "&lt;b&gt;raw&lt;/b&gt;"
    assert_not_includes html, "<b>raw</b>"
    assert_includes html, %(<h2 style="margin:24px 0 8px;)
    assert_includes html, %(<li style=")
    assert_includes html, %(href="https://example.com/changelog/2026-10")
    assert_includes html, "View in browser"
    assert_includes html, %(href="https://example.com/changelog")
    assert_includes html, "See everything that shipped"
    assert_includes html, %(href="https://example.com/shiplog/newsletter/unsubscribe/TOKEN")
    assert_includes html, %(href="https://example.com/shiplog/newsletter/preferences/PREF")
    assert_includes html, "Acme Inc., 1 Main Street, Springfield"
    assert_includes html, "because you subscribed to the Acme monthly summary"
    assert_includes html, "background-color:#ff0000;border-radius:6px;"
    assert_not_includes html, "<style"
  end

  test "the text part carries the plain text and the links" do
    text = announcement.text_part.body.to_s

    assert_includes text, "October recap\nMonthly update · October 2026"
    assert_includes text, "View in browser: https://example.com/changelog/2026-10"
    assert_includes text, "Intro with a link (https://example.com/x) and <b>raw</b>."
    assert_includes text, "- Dark mode"
    assert_includes text, "See everything that shipped: https://example.com/changelog"
    assert_includes text, "Unsubscribe: https://example.com/shiplog/newsletter/unsubscribe/TOKEN"
    assert_includes text, "Preferences: https://example.com/shiplog/newsletter/preferences/PREF"
    assert_includes text, "Acme Inc., 1 Main Street, Springfield"
    assert_not_includes text, "**"
  end

  test "a configured locale gets the translation and the chrome in that language" do
    Shiplog.config.locales = [ :es ]
    @entry.translations.create!(locale: "es", title: "Resumen de octubre", body: "Intro en español.", source_digest: @entry.translation_source_digest)
    mail = announcement(locale: "es")

    assert_equal "Resumen de octubre", mail.subject
    html = mail.html_part.body.to_s
    assert_includes html, "Intro en español."
    assert_includes html, "Ver en el navegador"
    assert_includes html, "Darme de baja"
    assert_includes html, "octubre 2026"
    assert_includes html, %(<html lang="es">)
    assert_includes mail.text_part.body.to_s, "Ver en el navegador: https://example.com/changelog/2026-10"
  end

  test "a locale that is not configured, or that I18n does not know, gets English" do
    Shiplog.config.locales = [ :xx ]
    assert_includes announcement(locale: "es").html_part.body.to_s, "View in browser"
    mail = announcement(locale: "xx")
    assert_includes mail.html_part.body.to_s, "View in browser"
    assert_equal "October recap", mail.subject
  end

  test "config.newsletter_mailer_options are merged into the message" do
    Shiplog.config.newsletter_mailer_options = { message_stream: "broadcast" }

    assert_equal "broadcast", announcement.header["message_stream"].to_s
    assert_nil Shiplog::NewsletterMailer.confirmation(subscriber).header["message_stream"], "transactional"
  end

  test "without a sender the message cannot be built" do
    Shiplog.config.newsletter_from = nil

    error = assert_raises(ArgumentError) { announcement.message }
    assert_includes error.message, "newsletter_from"
  end

  test "the preferences link falls back to the unsubscribe link, and the view link is left out without one" do
    Shiplog.config.announcements = :external
    html = Shiplog::NewsletterMailer.announcement(@entry, "a@example.com", locale: "en", unsubscribe_url: "https://example.com/u").html_part.body.to_s

    assert_not_includes html, "View in browser"
    assert_equal 2, html.scan(%(href="https://example.com/u")).size
  end

  test "a prepared Content is used as is" do
    content = Shiplog::Newsletter::Content.new(@entry, "en")
    def content.title = "Prepared title"

    assert_equal "Prepared title", announcement(content:).subject
  end

  test "the confirmation email links the confirmation page, in the subscriber's language" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.product_name = "Acme"
    record = subscriber(locale: "es")
    mail = Shiplog::NewsletterMailer.confirmation(record)

    assert_equal [ "ana@example.com" ], mail.to
    assert_equal [ "updates@example.com" ], mail.from
    assert_equal "Confirma tu suscripción al boletín de Acme", mail.subject
    assert_nil mail["List-Unsubscribe"]
    html = mail.html_part.body.to_s
    link = html[%r{https://example\.com/shiplog/newsletter/confirm/[A-Za-z0-9_-]+}]
    assert link
    assert_equal record, Shiplog::Newsletter::Tokens.subscriber_for(link.split("/").last)
    assert_includes html, "Confirmar mi suscripción"
    assert_includes html, "ana@example.com"
    assert_includes html, "Acme Inc., 1 Main Street, Springfield"
    assert_includes mail.text_part.body.to_s, link
  end

  test "the confirmation email is delivered through the test delivery method" do
    assert_emails 1 do
      Shiplog::NewsletterMailer.confirmation(subscriber).deliver_now
    end
  end

  test "the confirmation email can be built from the subscriber's id, and sends nothing for a row gone or confirmed since" do
    record = subscriber
    assert_equal [ "ana@example.com" ], Shiplog::NewsletterMailer.confirmation(record.id).to

    record.confirm!
    assert_kind_of ActionMailer::Base::NullMail, Shiplog::NewsletterMailer.confirmation(record.id).message, "nothing pending"
    record.destroy!
    assert_emails 0 do
      Shiplog::NewsletterMailer.confirmation(record.id).deliver_now
      Shiplog::NewsletterMailer.confirmation(0).deliver_now
    end
    assert_nothing_raised { perform_enqueued_jobs { Shiplog::NewsletterMailer.confirmation(record.id).deliver_later } }
  end

  test "without an unsubscribe URL the mailer makes the address's own, so a queued test send carries no token" do
    mail = Shiplog::NewsletterMailer.announcement(@entry, "boss@example.com", locale: "en")

    token = mail["List-Unsubscribe"].to_s[%r{unsubscribe/([A-Za-z0-9_-]+)>}, 1]
    assert_equal "boss@example.com", Shiplog::Newsletter::Tokens.email_for(token)
    assert_equal 2, mail.html_part.body.to_s.scan("https://example.com/shiplog/newsletter/unsubscribe/#{token}").size
  end

  private

  def subscriber(locale: "en")
    Shiplog::NewsletterSubscriber.create!(email: "ana@example.com", locale:, confirmation_nonce: Shiplog::NewsletterSubscriber.generate_nonce)
  end
end
