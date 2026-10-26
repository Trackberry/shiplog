module Shiplog
  module Admin
    module Entries
      class RewritesController < ApplicationController
        def create
          entry = Entry.find(params[:entry_id])
          RewriteEntryJob.perform_later(entry.id, force: true)
          redirect_to edit_entry_path(entry), notice: t("shiplog.admin.entries.rewrite_queued")
        end
      end
    end
  end
end
