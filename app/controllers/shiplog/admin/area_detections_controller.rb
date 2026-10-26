module Shiplog
  module Admin
    # "Detect areas": enqueues the backfill. The page shows no job state, only the flash.
    class AreaDetectionsController < ApplicationController
      def create
        unless Shiplog.config.rewriter
          return redirect_to areas_path, alert: t("shiplog.admin.areas.no_rewriter", default: "Detection needs config.rewriter, which is not set.")
        end

        DetectAreasJob.perform_later(recheck: params[:recheck] == "1")
        redirect_to areas_path, notice: t("shiplog.admin.areas.detection_queued", default: "Detection queued. Refresh in a moment.")
      end
    end
  end
end
