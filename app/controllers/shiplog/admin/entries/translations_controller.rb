module Shiplog
  module Admin
    module Entries
      # An admin's edit of an entry's translation (title and body) into one of config.locales. It is published
      # at once and kept until the English text changes: the translation is marked edited and made from the
      # entry's current English text, so it shows even if it was stale.
      class TranslationsController < ApplicationController
        before_action :set_entry_and_locale

        def update
          translation = @entry.translations.find_or_initialize_by(locale: @locale)
          translation.assign_attributes(translation_params)
          translation.assign_attributes(edited_by_admin: true, source_digest: @entry.translation_source_digest)
          if translation.save
            redirect_to edit_entry_path(@entry, inbox_filter_params), notice: t("shiplog.admin.entries.translations.saved", default: "Translation saved.")
          else
            redirect_to edit_entry_path(@entry, inbox_filter_params), alert: translation.errors.full_messages.to_sentence
          end
        end

        private

        def set_entry_and_locale
          @entry = Entry.find(params[:entry_id])
          @locale = params[:locale].to_s
          head :not_found unless Entry.translated_locale?(@locale)
        end

        def translation_params
          params.expect(translation: %i[title body])
        end
      end
    end
  end
end
