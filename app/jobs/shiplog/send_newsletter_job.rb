module Shiplog
  # Emails an approved announcement to every recipient (Newsletter::Recipients: the host's users, then the
  # confirmed subscribers, minus the unsubscribed and the duplicates), once per recipient. For each chunk of
  # NewsletterDelivery::CLAIM_SIZE it inserts the delivery rows first (one statement, skipping the rows that
  # exist) and emails only the recipients it inserted, touching each row right before its send, so a retried
  # job, a second click on Send or two workers never send twice: at most once per recipient. A failed delivery
  # is recorded on its row (never raised: the chunk goes on) for the admin's "Retry failed", which runs the job
  # with `retry_failed: true`: the failed and stalled rows are reclaimed in one statement, the ones reclaimed by
  # this run are sent again, and the ones whose recipient is gone end as failed with the reason.
  #
  # The announcement's Markdown is rendered once per locale (Newsletter::Content); each message is then built with
  # the recipient's own links. The job stops before anything is sent when the newsletter is off or the
  # announcement cannot be sent (Newsletter.blockers: not approved, missing translations, no sender...).
  class SendNewsletterJob < ApplicationJob
    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

    def perform(entry, retry_failed: false)
      return log_skip(entry, "the newsletter is off") unless Newsletter.enabled?

      blockers = Newsletter.blockers(entry)
      return log_skip(entry, "it cannot be sent: #{blockers.join(", ")}") if blockers.any?

      reclaimed = retry_failed ? NewsletterDelivery.reclaim(entry).to_set : Set.new
      contents = Hash.new { |hash, locale| hash[locale] = Newsletter::Content.new(entry, locale) }
      sent = 0
      Newsletter::Recipients.new.each_batch do |batch|
        batch.each_slice(NewsletterDelivery::CLAIM_SIZE) do |chunk|
          claimed = NewsletterDelivery.claim(entry, chunk).to_set
          chunk.each do |recipient|
            next unless claimed.include?(recipient.key) || reclaimed.delete?(recipient.key)

            sent += 1 if deliver(entry, recipient, contents[recipient.locale])
          end
        end
      end
      NewsletterDelivery.mark_missing(entry, reclaimed) # reclaimed, but no longer a recipient
      Rails.logger.info("[shiplog] Newsletter of entry #{entry.id}: #{sent} emails sent in this run")
    end

    private

    # Sends one email and records the outcome on the delivery row. True when it was sent.
    def deliver(entry, recipient, content)
      NewsletterDelivery.mark_sending(entry, recipient.key)
      NewsletterMailer.announcement(entry, recipient.email, locale: recipient.locale, content:,
        unsubscribe_url: Newsletter.unsubscribe_url(recipient.email), preferences_url: preferences_url(recipient)).deliver_now
      NewsletterDelivery.mark_sent(entry, recipient.key)
      true
    rescue StandardError => error
      NewsletterDelivery.mark_failed(entry, recipient.key, error)
      Rails.logger.error("[shiplog] Newsletter of entry #{entry.id} to #{recipient.key} failed: #{error.class}: #{NewsletterDelivery.scrub(error.message)}")
      false
    end

    # A subscriber's preferences page; a host user's own page when config.newsletter_unsubscribe_url gives one.
    def preferences_url(recipient)
      recipient.subscriber? ? Newsletter.preferences_url(recipient.record) : Newsletter.host_unsubscribe_url(recipient.record)
    end

    def log_skip(entry, reason)
      Rails.logger.info("[shiplog] Newsletter of entry #{entry.id} not sent: #{reason}")
    end
  end
end
