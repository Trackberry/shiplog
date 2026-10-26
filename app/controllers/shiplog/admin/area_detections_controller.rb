module Shiplog
  module Admin
    # "Detect areas": enqueues the backfill. The page shows no job state, only the flash.
    class AreaDetectionsController < ApplicationController
      def create
        DetectAreasJob.perform_later
        redirect_to areas_path, notice: t("shiplog.admin.areas.detection_queued", default: "Detection queued. Refresh in a moment.")
      end
    end
  end
end
