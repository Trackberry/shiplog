module Shiplog
  # The Atom feed of the latest published features and changes, and of the announcements when Shiplog renders
  # their pages: /changelog.atom.
  class ChangelogFeedsController < PublicController
    LIMIT = 50

    layout false
    before_action :set_area

    def show
      scope = Entry.published_changelog
      # Announcements have no area: a feed filtered by area leaves them out.
      scope = scope.or(Entry.published_announcements) if Shiplog.announcement_pages? && !@area
      scope = scope.newest_first
      scope = scope.where(area_id: @area.id) if @area
      @entries = scope.includes(:area).with_images_loaded.limit(LIMIT).to_a
      @entries.select!(&:permalink?) # no slug (or an invalid one) means no stable id: left out
      preload_translations(@entries)
      fresh_when etag: [ *shiplog_etag_parts, *shiplog_area_etag_parts, @entries.map { |entry| [ entry.id, entry.updated_at, entry.area_id ] },
        shiplog_image_etag_parts(@entries), shiplog_translation_etag_parts(@entries) ]
    end
  end
end
