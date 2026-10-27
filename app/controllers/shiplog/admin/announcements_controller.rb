module Shiplog
  module Admin
    # "Draft announcement for <month>" in the inbox: drafts the current or the previous month (see
    # Announcements.draftable_months) and opens it; a month that has an announcement already opens that one.
    class AnnouncementsController < ApplicationController
      def create
        month = Announcements.draftable_months.find { |candidate| candidate.strftime("%Y-%m") == params[:month].to_s }
        return head(:not_found) unless month && Shiplog.announcements?

        entry = Announcements.draft(month:) || Period.find_by(starts_on: month)&.announcement
        if entry
          redirect_to edit_entry_path(entry, inbox_filter_params), notice: t("shiplog.admin.announcements.drafted")
        else
          redirect_to root_path(inbox_filter_params), alert: t("shiplog.admin.announcements.nothing_to_announce")
        end
      end
    end
  end
end
