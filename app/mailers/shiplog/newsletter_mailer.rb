module Shiplog
  # The newsletter's emails: an announcement to one recipient, and the confirmation of a visitor's subscription.
  # Both have an HTML part (one 600px table column, styles inline, see app/views/shiplog/newsletter_mailer) and a
  # text part, in the recipient's language (the chrome from Shiplog's I18n keys, the announcement's text from its
  # translation). Hosts override the templates like any engine view. The sender is config.newsletter_from.
  class NewsletterMailer < ActionMailer::Base
    helper Shiplog::NewsletterMailerHelper

    default from: -> { sender! }

    # The announcement for `email` in `locale`. `unsubscribe_url` is the one-click target (the List-Unsubscribe
    # headers Gmail and Yahoo require; Newsletter.unsubscribe_url for the address when not given, so a queued test
    # send carries no token), `preferences_url` the page the footer's "Preferences" opens (a subscriber's page, or
    # the host's own for its users; nil shows the unsubscribe page instead). `content` is the locale's rendered
    # Content when the caller has it (SendNewsletterJob renders once per locale). config.newsletter_mailer_options
    # are merged into the message (e.g. Postmark's message_stream); they cannot change the recipient or the subject.
    def announcement(entry, email, locale:, unsubscribe_url: nil, preferences_url: nil, content: nil)
      @content = content || Newsletter::Content.new(entry, locale)
      @unsubscribe_url = unsubscribe_url || Newsletter.unsubscribe_url(email)
      @preferences_url = preferences_url || @unsubscribe_url
      headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
      headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
      headers["Precedence"] = "bulk"
      I18n.with_locale(Newsletter.i18n_locale(@content.locale)) do
        mail(**Shiplog.config.newsletter_mailer_options, to: email, subject: @content.subject)
      end
    end

    # The double opt-in email: a single-use link (valid 7 days) the subscriber must open, in the locale of the
    # page they subscribed on. `subscriber` is a NewsletterSubscriber, or its id when queued (deliver_later): a
    # row deleted or confirmed in the meantime sends nothing, quietly. Transactional: no mailer options, no
    # List-Unsubscribe.
    def confirmation(subscriber)
      @subscriber = subscriber.is_a?(NewsletterSubscriber) ? subscriber : NewsletterSubscriber.find_by(id: subscriber)
      @confirmation_url = @subscriber && Newsletter.confirmation_url(@subscriber)
      return unless @confirmation_url

      @product_name = Newsletter.product_name
      I18n.with_locale(Newsletter.i18n_locale(@subscriber.locale)) do
        mail(to: @subscriber.email, subject: t("shiplog.newsletter.mail.confirm_subject", product: Newsletter.product_name))
      end
    end

    private

    # The From address, or a clear error when none is configured (the job records it on the delivery row).
    def sender!
      Newsletter.from or raise ArgumentError, "[shiplog] config.newsletter_from is not set, so no newsletter email can be sent"
    end
  end
end
