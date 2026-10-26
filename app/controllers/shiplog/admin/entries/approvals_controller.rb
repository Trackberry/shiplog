module Shiplog
  module Admin
    module Entries
      class ApprovalsController < ApplicationController
        def create
          entry = Entry.find(params[:entry_id])
          entry.approve!(by: current_admin_name)
          redirect_to root_path(inbox_filter_params), notice: t("shiplog.admin.entries.approved")
        rescue ActiveRecord::RecordInvalid => error
          redirect_to edit_entry_path(entry, inbox_filter_params), alert: error.record.errors.full_messages.to_sentence
        end
      end
    end
  end
end
