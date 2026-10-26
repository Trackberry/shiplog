module Shiplog
  # The "what's new" count for host views: `helper Shiplog::UnseenHelper`, then
  # `shiplog_unseen_count(current_user.changelog_seen_at)`. Shiplog doesn't know about users, so the host
  # supplies the "last seen" time (and stamps it from config.on_changelog_seen).
  module UnseenHelper
    # The number of approved features and changes approved after `since` (all of them while it is nil), at most 99.
    def shiplog_unseen_count(since) = Shiplog.unseen_count(since:)
  end
end
