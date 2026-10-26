module Shiplog
  # Translates an approved entry into one locale of config.locales (see Translator). Enqueued when an entry is
  # approved and when the English text of an approved entry changes: a repeat for the same English text makes no
  # LLM call. `force: true` (the admin's Retranslate) ignores the stored digest and an admin's edit.
  #
  # A failure (the rewriter raised, or its reply was unusable) is logged and retried twice, with a growing wait,
  # then logged again and dropped: never an endless retry. The English text stays shown meanwhile.
  class TranslateEntryJob < ApplicationJob
    ATTEMPTS = 3

    retry_on StandardError, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
      entry, locale = job.arguments
      Rails.logger.error("[shiplog] Giving up translating entry #{entry.try(:id)} into #{locale} after #{ATTEMPTS} attempts: #{error.class}: #{error.message}")
    end
    # Declared after retry_on, which makes it win: an entry deleted since the job was enqueued is not an error.
    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

    def perform(entry, locale, force: false)
      Translator.new(entry, locale).call(force:)
    rescue StandardError => error
      Rails.logger.error("[shiplog] Translating entry #{entry.id} into #{locale} failed (attempt #{executions} of #{ATTEMPTS}): #{error.class}: #{error.message}")
      raise
    end
  end
end
