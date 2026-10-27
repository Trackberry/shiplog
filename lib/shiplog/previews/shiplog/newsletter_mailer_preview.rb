module Shiplog
  # Previews of the newsletter's emails, for hosts iterating on the design locally. Add the directory to your
  # preview paths (config/environments/development.rb):
  #
  #   config.action_mailer.preview_paths << Shiplog::Engine.root.join("lib/shiplog/previews").to_s
  #
  # then open /rails/mailers/shiplog/newsletter_mailer. The announcement is the newest approved one, or a sample
  # when there is none; ?locale=es previews a configured locale.
  class NewsletterMailerPreview < ActionMailer::Preview
    SAMPLE_BODY = <<~MARKDOWN.freeze
      This month we made imports faster and added a dark theme. Here is what shipped.

      ## Highlights

      ### Dark mode

      Switch to a dark theme from your settings. Easier on the eyes at night.

      ### Faster imports

      Spreadsheets with thousands of rows now import in seconds.

      ## Also improved

      - **Billing**: invoices show the tax breakdown.
      - **Exports**: CSV files keep leading zeros.
    MARKDOWN

    def announcement
      entry = Entry.published_announcements.order(released_on: :desc).first || sample_announcement
      locale = (params["locale"] || params[:locale]).presence || I18n.default_locale
      email = "preview@example.com"
      NewsletterMailer.announcement(entry, email, locale:, unsubscribe_url: Newsletter.unsubscribe_url(email),
        preferences_url: Newsletter.preferences_url(sample_subscriber))
    end

    def confirmation
      NewsletterMailer.confirmation(sample_subscriber)
    end

    private

    def sample_announcement
      month = Date.current.prev_month.beginning_of_month
      Entry.new(kind: "announcement", status: "approved", title: Period.month_name(month), body: SAMPLE_BODY,
        released_on: month.end_of_month, slug: month.strftime("%Y-%m"), subject: Period.new(starts_on: month, ends_on: month.end_of_month))
    end

    def sample_subscriber
      NewsletterSubscriber.new(email: "preview@example.com", locale: I18n.default_locale.to_s, token: "preview-token", confirmation_nonce: "preview-nonce")
    end
  end
end
