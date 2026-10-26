module Shiplog
  # The permalink page of a published feature or change: /changelog/:slug.
  class ChangelogEntriesController < PublicController
    after_action :notify_changelog_seen, only: :show

    def show
      @entry = Entry.published_changelog.find_by(slug: params[:slug])
      return head(:not_found) unless @entry

      @newer = @entry.newer_changelog_entry
      @older = @entry.older_changelog_entry
      [ @newer, @older ].each { |neighbour| neighbour&.ensure_slug! } # approved before 0.3.0: no permalink yet
      fresh_when etag: [ *shiplog_etag_parts, [ @entry, @newer, @older ].map { |entry| [ entry&.id, entry&.updated_at ] } ]
    end
  end
end
