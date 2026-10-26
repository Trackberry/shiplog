module Shiplog
  module Admin
    module Entries
      module Images
        # Moves an image up or down in its entry's order (params[:direction]).
        class MovesController < ApplicationController
          before_action { head :not_found unless Shiplog.images? }

          def create
            entry = Entry.find(params[:entry_id])
            return head(:not_found) unless entry.find_image(params[:image_id])

            entry.move_image(params[:image_id], params[:direction] == "up" ? :up : :down)
            redirect_to edit_entry_path(entry, inbox_filter_params), notice: t("shiplog.admin.entries.images.moved", default: "Image moved.")
          end
        end
      end
    end
  end
end
