module Shiplog
  # The newsletter: an approved announcement emailed, in each recipient's language, to the host's users who opted
  # in (config.newsletter_recipients, never stored) and to the visitors who subscribed through Shiplog's form
  # (NewsletterSubscriber, double opt-in). Approving publishes the announcement; sending is a separate, explicit
  # admin action (SendNewsletterJob, once per recipient: NewsletterDelivery). Off by default: config.newsletter.
  # An unsubscribe is honoured whatever the source of the address: Shiplog keeps a suppression row for it (the
  # one thing it stores about a host's user) and tells the host (config.on_newsletter_unsubscribe).
  module Newsletter
    def self.enabled? = Shiplog.newsletter?

    # Whether the newsletter's tables exist: the unsubscribe and preferences pages keep working while they do,
    # even with config.newsletter off (a link in an old email must still unsubscribe).
    def self.available? = NewsletterSubscriber.table_exists?

    # Why an announcement cannot be sent, as symbols the admin page explains (empty when it can): :not_approved,
    # :translations (a configured locale has no current translation, listed in `missing_locales`), :from,
    # :address and :base_url (config.newsletter_from, newsletter_address, and an origin for absolute links). A
    # test send (`test: true`) needs only a sender and an origin.
    def self.blockers(entry, test: false)
      blockers = []
      unless test
        blockers << :not_approved unless entry.approved?
        blockers << :translations if missing_locales(entry).any?
        blockers << :address if Shiplog.config.newsletter_address.blank?
      end
      blockers << :from if from.blank?
      blockers << :base_url if base_url.blank?
      blockers
    end

    def self.sendable?(entry) = blockers(entry).empty?

    # The configured locales with no current translation of the entry.
    def self.missing_locales(entry) = Shiplog.config.locales.reject { |locale| entry.translation(locale) }

    # The sender: config.newsletter_from, else ActionMailer's default From (the confirmation email needs one too).
    def self.from = Shiplog.config.newsletter_from.presence || ActionMailer::Base.default[:from].presence

    # The origin of the links in emails: config.canonical_url, else the host and protocol of
    # action_mailer.default_url_options (what every mailer uses), else nil (a blocker).
    def self.base_url
      return Shiplog.config.canonical_url if Shiplog.config.canonical_url

      options = ActionMailer::Base.default_url_options || {}
      host = options[:host].to_s.strip
      return if host.empty?

      protocol = options[:protocol].to_s.delete_suffix("://").presence || "https"
      port = options[:port].presence
      "#{protocol}://#{host}#{":#{port}" if port}"
    end

    # The absolute URL of an engine route (`:newsletter_preferences_path`, ...): the base URL plus the path, which
    # carries the engine's mount.
    def self.url(helper, *args) = "#{base_url}#{PublicLinks.path(helper, *args)}"

    # The page a newsletter's "View in browser" link opens: config.announcement_url (:external, called with the
    # entry and the locale; a failing or unsafe result is logged and gives no link), else the announcement's
    # own page (the default locale's URL: Shiplog cannot know how the host puts a locale in its URLs).
    def self.announcement_url(entry, locale)
      if Shiplog.config.announcements == :external
        callable = Shiplog.config.announcement_url
        return unless callable

        value = callable.call(entry, locale.to_sym)
        return value if Configuration.safe_url?(value) && value.match?(%r{\Ahttps?://}i)

        Rails.logger.warn("[shiplog] config.announcement_url gave no absolute http(s) URL for the newsletter of entry #{entry.id}: #{value.inspect}")
        nil
      else
        absolute(entry.public_url)
      end
    rescue StandardError => error
      Rails.logger.error("[shiplog] config.announcement_url failed for the newsletter of entry #{entry.id}: #{error.class}: #{error.message}")
      nil
    end

    def self.changelog_url = absolute(PublicLinks.changelog_url)

    # The one-click and footer unsubscribe target for any address, host user or subscriber: an encrypted token of
    # the email, so Shiplog stores nothing about the host's users until they unsubscribe (see Tokens).
    def self.unsubscribe_url(email) = url(:newsletter_unsubscription_path, Tokens.unsubscribe(email))

    def self.preferences_url(subscriber) = url(:newsletter_preferences_path, subscriber.token)

    # The confirmation link of a pending subscriber, or nil when there is no pending confirmation.
    def self.confirmation_url(subscriber)
      token = Tokens.confirmation(subscriber)
      url(:newsletter_confirmation_path, token) if token
    end

    # What a host user's footer links as "Preferences": config.newsletter_unsubscribe_url for the recipient, when
    # it gives a safe absolute URL (a failure is logged), else nil (the footer then links Shiplog's unsubscribe page).
    def self.host_unsubscribe_url(recipient)
      callable = Shiplog.config.newsletter_unsubscribe_url
      return unless callable

      value = callable.call(recipient)
      return value if Configuration.safe_url?(value) && value.match?(%r{\Ahttps?://}i)

      Rails.logger.warn("[shiplog] config.newsletter_unsubscribe_url gave no absolute http(s) URL for #{recipient.class.name}/#{recipient.id}: #{value.inspect}")
      nil
    rescue StandardError => error
      Rails.logger.error("[shiplog] config.newsletter_unsubscribe_url failed for #{recipient.class.name}/#{recipient.id}: #{error.class}: #{error.message}")
      nil
    end

    # Removes an address from both lists: Shiplog's row is marked unsubscribed (created as a suppression record
    # when there is none, so Recipients skips the address whatever the host's list says), and
    # config.on_newsletter_unsubscribe is called with the email so the host turns its user's setting off. A hook
    # that raises is logged; the visitor still sees the confirmation. False for an address that is not an email.
    def self.unsubscribe(email)
      subscriber = NewsletterSubscriber.suppress(email)
      return false unless subscriber

      notify_unsubscribe(subscriber.email)
      true
    end

    # The host's user opted in again: lifts the suppression. A row that was only a suppression record is deleted
    # (nothing is left to store); a visitor who had confirmed through the form is confirmed again. False when the
    # address was not suppressed.
    def self.resubscribe(email)
      subscriber = NewsletterSubscriber.find_by_email(email)
      return false unless subscriber&.unsubscribed?

      subscriber.never_confirmed? ? subscriber.destroy! : subscriber.resubscribe!
      true
    end

    def self.notify_unsubscribe(email)
      Shiplog.config.on_newsletter_unsubscribe&.call(email)
    rescue StandardError => error
      Rails.logger.error("[shiplog] on_newsletter_unsubscribe failed for #{digest(email)}: #{error.class}: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}")
    end
    private_class_method :notify_unsubscribe

    # A short digest of an address, for log lines (never the address itself).
    def self.digest(email) = "email:#{Digest::SHA256.hexdigest(email.to_s.strip.downcase).first(12)}"

    # What the subscribe form's per-address rate limit counts: the address lowercased, without a +tag, and
    # without dots for Gmail (where they are ignored), digested so the cache never holds an address.
    def self.rate_limit_key(email)
      local, domain = email.to_s.strip.downcase.split("@", 2)
      local = local.to_s.split("+", 2).first.to_s
      if %w[gmail.com googlemail.com].include?(domain)
        local = local.delete(".")
        domain = "gmail.com"
      end
      Digest::SHA256.hexdigest("#{local}@#{domain}")
    end

    # The locale a recipient's email is written in: theirs when it is the default or a configured one, else the
    # default (as a String).
    def self.locale_for(locale) = NewsletterSubscriber.resolve_locale(locale)

    # The locale I18n can switch to for the email's chrome and the public pages: the one given when the host's
    # I18n knows it, else the default (a configured translation locale need not be an available one).
    def self.i18n_locale(locale)
      candidate = locale.to_s.presence
      candidate && I18n.locale_available?(candidate) ? candidate.to_sym : I18n.default_locale
    end

    # The product's name for the email texts: config.product_name, else the "shiplog.newsletter.product" text.
    def self.product_name = Shiplog.config.product_name.presence || I18n.t("shiplog.newsletter.product", default: "Product updates")

    # An absolute URL for a path (or an absolute URL as is), with the origin the emails use (base_url); nil for a
    # blank value or without a base URL.
    def self.absolute_url(url)
      return if url.blank?
      return url if url.match?(%r{\Ahttps?://}i)
      return unless base_url

      "#{base_url}#{url}"
    end

    def self.absolute(url) = absolute_url(url)
    private_class_method :absolute
  end
end
