module Shiplog
  module Admin
    module Areas
      # Moves every entry of an area to another one and deletes the first.
      class MergesController < ApplicationController
        def create
          area = Area.find(params[:area_id])
          target = Area.find_by(id: params[:target_id])
          if target.nil? || target == area
            redirect_to areas_path, alert: t("shiplog.admin.areas.merge_target", default: "Choose another area to merge into.")
          else
            area.merge_into!(target)
            redirect_to areas_path, notice: t("shiplog.admin.areas.merged", from: area.name, into: target.name, default: "%{from} merged into %{into}.")
          end
        end
      end
    end
  end
end
