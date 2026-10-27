module Shiplog
  module Admin
    module Entries
      # Sending an announcement as the newsletter: `show` is the confirmation step (the recipient count per locale,
      # after deduplication), `create` enqueues Shiplog::SendNewsletterJob. Both refuse while Newsletter.blockers
      # lists a reason (not approved, a missing translation, no sender, no address, no origin for links).
      class NewslettersController < ApplicationController
        before_action :set_announcement

        def show
          @blockers = Newsletter.blockers(@entry)
          @progress = NewsletterDelivery.progress(@entry)
          @counts = Newsletter::Recipients.new.counts_by_locale
        rescue StandardError => error
          # The page names the class only: a message could carry an address or a secret. The log has the rest.
          Rails.logger.error("[shiplog] Listing the newsletter's recipients failed: #{error.class}: #{NewsletterDelivery.scrub(error.message)}")
          @counts = {}
          @recipients_error = error.class.name
        end

        def create
          blockers = Newsletter.blockers(@entry)
          if blockers.any?
            redirect_to edit_entry_path(@entry, inbox_filter_params), alert: t("shiplog.admin.newsletter.send_blocked", reasons: blockers.map { |blocker| t("shiplog.admin.newsletter.blockers.#{blocker}", locales: Newsletter.missing_locales(@entry).join(", ")) }.join(", "))
          else
            SendNewsletterJob.perform_later(@entry)
            redirect_to edit_entry_path(@entry, inbox_filter_params), notice: t("shiplog.admin.newsletter.queued")
          end
        end

        private

        def set_announcement
          @entry = Entry.find(params[:entry_id])
          head :not_found unless @entry.announcement? && Shiplog.newsletter?
        end
      end
    end
  end
end
