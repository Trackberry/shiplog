module Shiplog
  # The Atom feed of the latest published features and changes: /changelog.atom.
  class ChangelogFeedsController < PublicController
    LIMIT = 50

    layout false
    before_action :set_area

    def show
      scope = Entry.published_changelog.newest_first
      scope = scope.where(area_id: @area.id) if @area
      @entries = scope.includes(:area).limit(LIMIT).to_a
      @entries.select!(&:permalink?) # no slug (or an invalid one) means no stable id: left out
      fresh_when etag: [ *shiplog_etag_parts, *shiplog_area_etag_parts, @entries.map { |entry| [ entry.id, entry.updated_at, entry.area_id ] } ]
    end
  end
end
