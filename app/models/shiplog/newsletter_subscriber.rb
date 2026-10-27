module Shiplog
  # An address the newsletter knows: a visitor who subscribed through Shiplog's form, or an address that
  # unsubscribed (a suppression record kept for the host's own users too, who are otherwise never stored; see
  # Newsletter.unsubscribe). Double opt-in: a row starts pending with a single-use `confirmation_nonce`, the
  # secret of the confirmation link (valid 7 days, see Newsletter::Tokens); following it sets `confirmed_at` and
  # clears the nonce. `unsubscribed_at` keeps an unsubscribed address suppressed: subscribing again through the
  # form confirms again, and "delete my data" on the preferences page removes the row (and its delivery rows).
  # `token` reaches that page without an account and is rotated after each change there; `source` is the page
  # the visitor signed up on (a consent record). Emails are stored lowercased and stripped, unique on lower(email).
  class NewsletterSubscriber < ApplicationRecord
    EMAIL_MAX_LENGTH = 254
    SOURCE_MAX_LENGTH = 255
    # Pending rows untouched for this long are deleted (see purge_pending and PurgeNewsletterJob).
    PENDING_FOR = 30.days
    STATUSES = %w[pending confirmed unsubscribed].freeze
    TOKEN_LENGTH = 32

    has_secure_token :token, length: TOKEN_LENGTH

    normalizes :email, with: ->(email) { email.to_s.strip.downcase }
    normalizes :source, with: ->(source) { Shiplog::NewsletterSubscriber.clean_source(source) }

    validates :email, presence: true, length: { maximum: EMAIL_MAX_LENGTH }, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :locale, presence: true

    # Nothing about an address outlives its row.
    after_destroy { NewsletterDelivery.where(recipient_key:).delete_all }

    scope :confirmed, -> { where.not(confirmed_at: nil).where(unsubscribed_at: nil) }
    scope :pending, -> { where(confirmed_at: nil, unsubscribed_at: nil) }
    scope :unsubscribed, -> { where.not(unsubscribed_at: nil) }
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    # The locales a subscriber can pick: the default one and config.locales, as strings.
    def self.allowed_locales = [ I18n.default_locale.to_s, *Shiplog.config.locales.map(&:to_s) ].uniq

    # `locale` when it is one of the allowed ones, else the default locale.
    def self.resolve_locale(locale) = locale.to_s.presence_in(allowed_locales) || I18n.default_locale.to_s

    # A source worth recording: a same-site path ("/changelog", not "//evil" or a URL), control characters
    # removed, at most SOURCE_MAX_LENGTH; nil for anything else.
    def self.clean_source(value)
      return unless value.is_a?(String)

      path = value.gsub(/[[:cntrl:]]/, "").strip
      path if path.length.between?(1, SOURCE_MAX_LENGTH) && path.start_with?("/") && Configuration.safe_url?(path)
    end

    # The row for an address, whatever its case or surrounding spaces, or nil.
    def self.find_by_email(email)
      normalized = email.to_s.strip.downcase
      where("lower(email) = ?", normalized).first if normalized.present?
    end

    # What the form does: makes the address pending and emails it a confirmation link. The subscriber, or nil
    # for an address that is not an email. A confirmed subscriber gets no email (the caller answers the same
    # thing either way, so the form reveals nothing); a pending one gets a fresh link (the previous one stops
    # working); an unsubscribed one must confirm again, and stays suppressed until then. An existing row keeps
    # its locale and source: an anonymous submission does not rewrite what the person chose.
    def self.subscribe(email, locale:, source: nil)
      retrying_on_conflict do
        subscriber = find_by_email(email) || new(email:, locale: resolve_locale(locale), source:)
        next unless subscriber.valid?
        next subscriber if subscriber.confirmed?

        subscriber.update!(confirmed_at: nil, confirmation_nonce: generate_nonce)
        NewsletterMailer.confirmation(subscriber.id).deliver_later
        subscriber
      end
    end

    # Marks an address unsubscribed, creating the row when there is none (the host's user who never used the
    # form): the suppression record Newsletter::Recipients honours whatever the source of the address.
    def self.suppress(email)
      retrying_on_conflict do
        subscriber = find_by_email(email) || new(email:, locale: I18n.default_locale.to_s)
        next unless subscriber.valid?

        subscriber.unsubscribe!
        subscriber
      end
    end

    # Runs the block again, once, when two requests create the same address at the same time (the unique index
    # catches the second insert, which then finds the first row).
    def self.retrying_on_conflict
      attempts = 0
      begin
        transaction(requires_new: true) { yield }
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 2
        raise
      end
    end
    private_class_method :retrying_on_conflict

    def self.generate_nonce = SecureRandom.base58(TOKEN_LENGTH)

    # Deletes the pending rows untouched for `older_than` (an address that never confirmed; a re-sent
    # confirmation touches the row). Returns how many.
    def self.purge_pending(older_than: PENDING_FOR)
      pending.where(updated_at: ...older_than.ago).delete_all
    end

    # Subscribers whose address contains the query (case-insensitive); all of them for a blank query.
    def self.search(query)
      term = query.to_s.squish.first(EMAIL_MAX_LENGTH)
      term.present? ? where("email ILIKE ?", "%#{sanitize_sql_like(term)}%") : all
    end

    # { "es" => { "confirmed" => 12, "pending" => 3, "unsubscribed" => 1 }, ... }, every status present.
    def self.counts_by_locale
      rows = group(:locale, Arel.sql("confirmed_at IS NOT NULL"), Arel.sql("unsubscribed_at IS NOT NULL")).count
      rows.each_with_object(Hash.new { |hash, key| hash[key] = STATUSES.index_with(0) }) do |((locale, confirmed, unsubscribed), count), counts|
        counts[locale][status_for(confirmed:, unsubscribed:)] += count
      end
    end

    # The status from the two timestamps: unsubscribed wins (a suppression record, even while reconfirming).
    def self.status_for(confirmed:, unsubscribed:)
      return "unsubscribed" if unsubscribed
      confirmed ? "confirmed" : "pending"
    end

    def status = self.class.status_for(confirmed: confirmed_at.present?, unsubscribed: unsubscribed_at.present?)
    def confirmed? = status == "confirmed"
    def pending? = status == "pending"
    def unsubscribed? = status == "unsubscribed"

    # Whether the row is only a suppression record: the address never confirmed a subscription.
    def never_confirmed? = confirmed_at.nil?

    # The confirmation link was followed: the address receives the newsletter (and is no longer suppressed). The
    # nonce is spent: the link cannot be used again.
    def confirm!
      update!(confirmed_at: confirmed_at || Time.current, unsubscribed_at: nil, confirmation_nonce: nil)
    end

    # Marks the row unsubscribed (kept as a suppression record) and voids a pending confirmation link.
    # Newsletter.unsubscribe also tells the host.
    def unsubscribe!
      update!(unsubscribed_at: unsubscribed_at || Time.current, confirmation_nonce: nil)
    end

    # "Resubscribe" on the preferences page, reached through the token (which proves the mailbox), or the host's
    # user opting in again (Newsletter.resubscribe): no new confirmation needed.
    def resubscribe!
      update!(unsubscribed_at: nil, confirmed_at: confirmed_at || Time.current)
    end

    # A new preferences token: the one in the link just used stops working (links travel through logs and inboxes).
    def rotate_token! = regenerate_token

    # The key of the delivery row of a newsletter to this subscriber (see NewsletterDelivery).
    def recipient_key = "Subscriber/#{id}"
  end
end
