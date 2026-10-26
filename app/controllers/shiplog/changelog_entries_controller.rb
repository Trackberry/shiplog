module Shiplog
  # The permalink page of a published feature or change: /changelog/:slug.
  class ChangelogEntriesController < PublicController
    def show
      @entry = Entry.published_changelog.with_images_loaded.find_by(slug: params[:slug])
      return pass_to_host_routes unless @entry

      notify_changelog_seen
      @newer = @entry.newer_changelog_entry
      @older = @entry.older_changelog_entry
      preload_translations(@entry, @newer, @older)
      fresh_when etag: [ *shiplog_etag_parts, *shiplog_area_etag_parts, [ @entry, @newer, @older ].map { |entry| [ entry&.id, entry&.updated_at, entry&.area_id ] },
        shiplog_image_etag_parts([ @entry ]), shiplog_translation_etag_parts([ @entry, @newer, @older ]) ]
    end

    private

    # The engine is usually mounted at "/", so /changelog/:slug can shadow a host route below the changelog
    # path (/changelog/archive, declared after the mount). An unknown slug answers 404 with X-Cascade: pass,
    # which makes the router try the routes after the engine's mount; if none matches, the host's own 404 shows.
    def pass_to_host_routes
      response.set_header("X-Cascade", "pass")
      head :not_found
    end
  end
end
