module Shiplog
  # Backfills product areas for entries that have none (see AreaDetector). Enqueued by the admin's Areas page.
  # A failure is logged and recorded for the Areas page (Setting "area_detection"), never raised: the job is not
  # retried, the admin clicks again once the cause (usually the rewriter) is fixed.
  class DetectAreasJob < ApplicationJob
    SETTING = "area_detection".freeze
    MAX_ERROR_CHARS = 500

    # recheck: true first makes the entries the AI left unplaced eligible again.
    def perform(recheck: false)
      assigned = AreaDetector.new.call(recheck:)
      Setting.write(SETTING, at: Time.current.iso8601, assigned:) if assigned # nil: another run was in progress
    rescue StandardError => error
      Rails.logger.error("[shiplog] Detect areas failed: #{error.class}: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}")
      Setting.write(SETTING, at: Time.current.iso8601, error: "#{error.class}: #{error.message}".truncate(MAX_ERROR_CHARS))
    end
  end
end
