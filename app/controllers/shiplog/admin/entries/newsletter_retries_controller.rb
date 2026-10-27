module Shiplog
  module Admin
    module Entries
      # "Retry failed": runs Shiplog::SendNewsletterJob again for the deliveries that failed, and for the pending
      # ones older than an hour (a worker died with them claimed; see NewsletterDelivery.reclaim).
      class NewsletterRetriesController < ApplicationController
        def create
          entry = Entry.find(params[:entry_id])
          return head(:not_found) unless entry.announcement? && Shiplog.newsletter?

          SendNewsletterJob.perform_later(entry, retry_failed: true)
          redirect_to edit_entry_path(entry, inbox_filter_params), notice: t("shiplog.admin.newsletter.retry_queued")
        end
      end
    end
  end
end
