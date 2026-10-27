module Shiplog
  # Housekeeping of the newsletter's tables, to schedule weekly like ScanChangesJob (see the README's Scheduling
  # section): deletes the subscribers who never confirmed within 30 days (NewsletterSubscriber::PENDING_FOR: an
  # address typed by someone else, or a confirmation email that never arrived) and the delivery rows older than
  # 180 days (NewsletterDelivery::RETENTION: the idempotency record of a send long done). Confirmed and
  # unsubscribed rows are never touched. Returns { subscribers:, deliveries: } counts.
  class PurgeNewsletterJob < ApplicationJob
    def perform
      subscribers = NewsletterSubscriber.purge_pending
      deliveries = NewsletterDelivery.purge
      Rails.logger.info("[shiplog] Purged #{subscribers} unconfirmed newsletter #{subscribers == 1 ? "subscriber" : "subscribers"} and #{deliveries} old delivery #{deliveries == 1 ? "row" : "rows"}")
      { subscribers:, deliveries: }
    end
  end
end
