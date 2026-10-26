module Shiplog
  module Admin
    module Entries
      module Translations
        # Translates the entry into the locale again, ignoring the stored digest and an admin's edit.
        class RetranslationsController < ApplicationController
          def create
            entry = Entry.find(params[:entry_id])
            locale = params[:translation_locale].to_s
            return head(:not_found) unless Entry.translated_locale?(locale)

            back = edit_entry_path(entry, inbox_filter_params)
            return redirect_to(back, alert: t("shiplog.admin.entries.translations.only_approved", default: "Only approved entries are translated.")) unless entry.approved?
            return redirect_to(back, alert: t("shiplog.admin.entries.translations.no_rewriter", default: "Translating needs config.rewriter, which is not set.")) unless Shiplog.config.rewriter

            TranslateEntryJob.perform_later(entry, locale.to_sym, force: true)
            redirect_to back, notice: t("shiplog.admin.entries.translations.queued", default: "Translation queued. Refresh in a moment.")
          end
        end
      end
    end
  end
end
