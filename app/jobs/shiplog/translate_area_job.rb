module Shiplog
  # Translates an area's name into every locale of config.locales with one LLM call (see AreaTranslator).
  # Enqueued when an area is created or renamed, by "Translate names" (with `force: true`) and by
  # `shiplog:translate_approved`. Without force a locale that has a name is left alone, an admin's edit included;
  # a repeat when every locale has one makes no LLM call.
  #
  # A failure (the rewriter raised, or its reply was unusable) is logged and retried twice, with a growing wait,
  # then logged again and dropped: never an endless retry. The English name stays shown meanwhile.
  class TranslateAreaJob < ApplicationJob
    ATTEMPTS = 3

    retry_on StandardError, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
      Rails.logger.error("[shiplog] Giving up translating area #{job.arguments.first.try(:id)} after #{ATTEMPTS} attempts: #{error.class}: #{error.message}")
    end
    # Declared after retry_on, which makes it win: an area deleted since the job was enqueued is not an error.
    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

    def perform(area, force: false)
      AreaTranslator.new(area).call(force:)
    rescue StandardError => error
      Rails.logger.error("[shiplog] Translating area #{area.id} failed (attempt #{executions} of #{ATTEMPTS}): #{error.class}: #{error.message}")
      raise
    end
  end
end
