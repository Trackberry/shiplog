module Shiplog
  # The Atom feed of the latest published features and changes: /changelog.atom.
  class ChangelogFeedsController < PublicController
    LIMIT = 50

    layout false

    def show
      @entries = Entry.published_changelog.newest_first.limit(LIMIT).to_a
      @entries.each(&:ensure_slug!)
      fresh_when etag: [ *shiplog_etag_parts, @entries.map { |entry| [ entry.id, entry.updated_at ] } ]
    end
  end
end
