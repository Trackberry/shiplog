module Shiplog
  # Calls config.on_announcement_approved with an approved announcement, and sends the
  # `announcement_approved.shiplog` notification, once its translations into every configured locale are current
  # (or cannot be made: no rewriter). Enqueued when an announcement is approved and after each translation of one;
  # whichever run finds it ready announces it, once per approval (Entry#announce!).
  #
  # The hook runs inside the announcement's row lock and transaction: keep it fast (enqueue your own job). A hook
  # that raises, or a worker that dies mid-hook, leaves the announcement unannounced, and the retry calls it again;
  # after the last attempt the error is logged and the admin can "Notify now". `force: true` (that button) does not
  # wait for translations.
  class AnnounceJob < ApplicationJob
    ATTEMPTS = 3
    EVENT = "announcement_approved.shiplog".freeze

    retry_on StandardError, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
      Rails.logger.error("[shiplog] Giving up announcing entry #{job.arguments.first.try(:id)} after #{ATTEMPTS} attempts: #{error.class}: #{error.message}")
    end
    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

    def perform(entry, force: false)
      return unless Shiplog.announcements?

      entry.announce!(force:) do
        ActiveSupport::Notifications.instrument(EVENT, announcement: entry) do
          Shiplog.config.on_announcement_approved&.call(entry)
        end
      end
    end
  end
end
