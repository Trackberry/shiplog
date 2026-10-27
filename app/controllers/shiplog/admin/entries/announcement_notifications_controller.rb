module Shiplog
  module Admin
    module Entries
      # "Notify now" on an approved announcement your app was not told about yet: the hook gave up after its retries,
      # or a translation never came. Calls config.on_announcement_approved without waiting for translations (the
      # hook gets the English text where one is missing); an announcement already announced is left alone.
      class AnnouncementNotificationsController < ApplicationController
        def create
          entry = Entry.find(params[:entry_id])
          return head(:not_found) unless entry.announcement?

          AnnounceJob.perform_later(entry, force: true)
          redirect_to edit_entry_path(entry, inbox_filter_params), notice: t("shiplog.admin.announcements.notify_queued")
        end
      end
    end
  end
end
