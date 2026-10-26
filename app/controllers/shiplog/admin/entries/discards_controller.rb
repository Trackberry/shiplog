module Shiplog
  module Admin
    module Entries
      class DiscardsController < ApplicationController
        before_action :set_entry

        def create
          @entry.discard!(reason: params[:reason].to_s.strip.presence)
          redirect_to root_path, notice: t("shiplog.admin.entries.discarded")
        end

        def destroy
          @entry.restore!
          redirect_to root_path, notice: t("shiplog.admin.entries.restored")
        end

        private

        def set_entry
          @entry = Entry.find(params[:entry_id])
        end
      end
    end
  end
end
