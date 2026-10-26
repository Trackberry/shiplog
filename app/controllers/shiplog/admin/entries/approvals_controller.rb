module Shiplog
  module Admin
    module Entries
      class ApprovalsController < ApplicationController
        def create
          entry = Entry.find(params[:entry_id])
          entry.approve!(by: current_admin_name)
          respond_inline(entry, :approved)
        rescue ActiveRecord::RecordInvalid => error
          respond_inline_error(error.record.errors.full_messages.to_sentence, edit_entry_path(entry, inbox_filter_params))
        end
      end
    end
  end
end
