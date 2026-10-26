module Shiplog
  module Admin
    # The Areas page: product areas with their entry counts; rename, delete. Reordering, merging and detection
    # are their own small controllers.
    class AreasController < ApplicationController
      before_action :set_area, only: %i[update destroy]

      def index
        @areas = Area.ordered.to_a
        @counts = Area.entry_counts
      end

      def update
        if @area.update(params.expect(area: %i[name]))
          redirect_to areas_path, notice: t("shiplog.admin.areas.renamed", default: "Area renamed.")
        else
          redirect_to areas_path, alert: @area.errors.full_messages.to_sentence
        end
      end

      def destroy
        @area.destroy!
        redirect_to areas_path, notice: t("shiplog.admin.areas.deleted", default: "Area deleted. Its entries have no area now.")
      end

      private

      def set_area
        @area = Area.find(params[:id])
      end
    end
  end
end
