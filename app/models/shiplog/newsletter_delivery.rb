module Shiplog
  # One newsletter email to one recipient: a row per announcement and recipient key ("User/42" for the host's
  # users, "Subscriber/7" for Shiplog's), unique on both. The row is inserted BEFORE the email is sent (status
  # "pending"), then marked "sent" or "failed" (with the error, scrubbed of any address). So a retried job, a
  # worker that runs twice or a second click on Send never emails anyone twice: at most once per recipient. No
  # email address is stored here; a subscriber's rows go with its row, and rows older than RETENTION are purged
  # (PurgeNewsletterJob). The admin's "Retry failed" sends the failed rows again, and the pending rows untouched
  # for STALLED_AFTER, which a dying worker left behind (a row is touched right before its email is sent).
  class NewsletterDelivery < ApplicationRecord
    STALLED_AFTER = 1.hour
    RETENTION = 180.days
    # How many rows a run claims at once: small, so a claimed row waits little before its send (and its touch).
    CLAIM_SIZE = 100
    ERROR_MAX_LENGTH = 500
    EMAIL_LIKE = /[^\s@<>()\[\]"']+@[^\s@<>()\[\]"']+/
    MISSING_RECIPIENT = "Shiplog::Newsletter::MissingRecipient: not among the recipients anymore".freeze

    belongs_to :announcement, class_name: "Shiplog::Entry", inverse_of: :newsletter_deliveries

    enum :status, %w[pending sent failed].index_by(&:itself), validate: true

    scope :stalled, -> { pending.where(updated_at: ...STALLED_AFTER.ago) }

    # { sent:, failed:, pending:, stalled: } for an announcement; two COUNT queries.
    def self.progress(announcement)
      scope = where(announcement:)
      counts = scope.group(:status).count
      { sent: counts.fetch("sent", 0), failed: counts.fetch("failed", 0), pending: counts.fetch("pending", 0), stalled: scope.stalled.count }
    end

    # Inserts a pending row for each recipient that has none yet (one statement) and returns the keys of the rows
    # inserted: the recipients this run may email. Rows that exist already (sent, failed, or pending in another
    # run) are left alone.
    def self.claim(announcement, recipients)
      return [] if recipients.empty?

      rows = recipients.map { |recipient| { announcement_id: announcement.id, recipient_key: recipient.key, locale: recipient.locale, status: "pending" } }
      insert_all(rows, unique_by: [ :announcement_id, :recipient_key ], returning: [ :recipient_key ]).rows.flatten
    end

    # Puts the failed and stalled rows of an announcement back to pending in one statement and returns the keys
    # it changed: two retries at once each get their own rows, and a run sends only what it reclaimed itself.
    # The one place a recipient can receive the email twice: a stalled row whose email did leave before the
    # worker died. The admin triggers it knowingly.
    def self.reclaim(announcement)
      sql = sanitize_sql_array([ <<~SQL.squish, { now: Time.current, id: announcement.id, stalled_before: STALLED_AFTER.ago } ])
        UPDATE #{table_name} SET status = 'pending', error = NULL, updated_at = :now
        WHERE announcement_id = :id AND (status = 'failed' OR (status = 'pending' AND updated_at < :stalled_before))
        RETURNING recipient_key
      SQL
      with_connection { |connection| connection.exec_query(sql, "Shiplog::NewsletterDelivery Reclaim").rows.flatten }
    end

    # Touches the row right before its email is sent, so a row in flight never looks stalled.
    def self.mark_sending(announcement, key)
      where(announcement:, recipient_key: key).update_all(updated_at: Time.current)
    end

    def self.mark_sent(announcement, key)
      where(announcement:, recipient_key: key).update_all(status: "sent", sent_at: Time.current, error: nil, updated_at: Time.current)
    end

    # Records a failure as the exception's class and its message with anything address-like removed.
    def self.mark_failed(announcement, key, error)
      where(announcement:, recipient_key: key).update_all(status: "failed", error: "#{error.class}: #{scrub(error.message)}", updated_at: Time.current)
    end

    # Reclaimed rows whose recipient is gone (a deleted subscriber, a user that left the host's list): failed,
    # with the reason, rather than pending forever.
    def self.mark_missing(announcement, keys)
      return if keys.empty?

      where(announcement:, recipient_key: keys.to_a, status: "pending").update_all(status: "failed", error: MISSING_RECIPIENT, updated_at: Time.current)
    end

    # Deletes the rows older than `older_than`, whatever their status. Returns how many.
    def self.purge(older_than: RETENTION)
      where(created_at: ...older_than.ago).delete_all
    end

    def self.scrub(text) = text.to_s.gsub(EMAIL_LIKE, "[email]").first(ERROR_MAX_LENGTH)
  end
end
