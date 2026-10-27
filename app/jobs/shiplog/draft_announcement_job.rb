module Shiplog
  # Drafts the announcement of a month (the previous one by default) and enqueues its rewrite. Schedule it once a
  # month, early in the month (see the README's Scheduling section); running it again is harmless.
  class DraftAnnouncementJob < ApplicationJob
    def perform(month = nil)
      Announcements.draft(month: month || Date.current.prev_month)
    end
  end
end
