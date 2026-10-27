module Shiplog
  # Previews of the newsletter's emails, for hosts iterating on the design locally. Add the directory to your
  # preview paths (config/environments/development.rb):
  #
  #   config.action_mailer.preview_paths << Shiplog::Engine.root.join("lib/shiplog/previews").to_s
  #
  # then open /rails/mailers/shiplog/newsletter_mailer. The announcement is the newest approved one (with the
  # month's real feature highlights), or a sample with sample highlights when there is none (no database rows
  # needed); ?locale=es previews a configured locale.
  class NewsletterMailerPreview < ActionMailer::Preview
    SAMPLE_BODY = <<~MARKDOWN.freeze
      This month we made imports faster and added a dark theme. Here is what shipped.

      ## Highlights

      ### Dark mode

      Switch to a dark theme from your settings. Easier on the eyes at night.

      ### Faster imports

      Spreadsheets with thousands of rows now import in seconds.

      ## Also improved

      ### Billing

      - Invoices show the tax breakdown.
      - Refunds appear on the next statement.

      ### Exports

      - CSV files keep leading zeros.
    MARKDOWN

    SAMPLE_HIGHLIGHTS = [
      { title: "Dark mode", summary: "Switch to a dark theme from your settings, easier on the eyes at night.", slug: "dark-mode",
        image_url: "https://placehold.co/1200x700/png?text=Dark+mode", image_width: 1200, image_height: 700 },
      { title: "Faster imports", summary: "Spreadsheets with thousands of rows now import in seconds.", slug: "faster-imports",
        image_url: "https://placehold.co/1200x700/png?text=Faster+imports", image_width: 1200, image_height: 700 },
      { title: "Shared views", summary: "Save a filtered view and share it with your team.", slug: "shared-views", image_url: nil }
    ].freeze

    def announcement
      entry = Entry.published_announcements.order(released_on: :desc).first
      locale = (params["locale"] || params[:locale]).presence || I18n.default_locale
      email = "preview@example.com"
      content = entry ? nil : Newsletter::Content.new(sample_announcement, locale, highlights: sample_highlights)
      NewsletterMailer.announcement(entry || content.entry, email, locale:, content:, unsubscribe_url: Newsletter.unsubscribe_url(email),
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

    # Three cards, two with a (placeholder) screenshot, linking to sample permalinks under the email's origin.
    def sample_highlights
      SAMPLE_HIGHLIGHTS.map do |sample|
        Newsletter::Content::Highlight.new(title: sample[:title], summary: sample[:summary], url: Newsletter.absolute_url(PublicLinks.path(:changelog_entry_path, sample[:slug])),
          image_url: sample[:image_url], image_alt: sample[:title], image_width: sample[:image_width], image_height: sample[:image_height])
      end
    end

    def sample_subscriber
      NewsletterSubscriber.new(email: "preview@example.com", locale: I18n.default_locale.to_s, token: "preview-token", confirmation_nonce: "preview-nonce")
    end
  end
end
