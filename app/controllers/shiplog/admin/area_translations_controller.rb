module Shiplog
  module Admin
    # "Translate names": enqueues a TranslateAreaJob, which only fills in missing names (edits are kept), for every area that has no name in some configured
    # locale. The page shows no job state, only the flash.
    class AreaTranslationsController < ApplicationController
      def create
        if Shiplog.config.locales.empty?
          return redirect_to areas_path, alert: t("shiplog.admin.areas.no_locales", default: "Translating names needs config.locales, which is empty.")
        end
        unless Shiplog.config.rewriter
          return redirect_to areas_path, alert: t("shiplog.admin.areas.no_rewriter_translate", default: "Translating names needs config.rewriter, which is not set.")
        end

        count = Area.enqueue_missing_translations(force: false)
        redirect_to areas_path, notice: t("shiplog.admin.areas.translation_queued", count:, default: { one: "Translation queued for %{count} area. Refresh in a moment.", other: "Translation queued for %{count} areas. Refresh in a moment." })
      end
    end
  end
end
