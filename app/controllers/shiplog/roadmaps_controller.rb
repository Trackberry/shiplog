module Shiplog
  class RoadmapsController < PublicController
    helper Shiplog::RoadmapHelper

    def show
      @columns = Roadmap.new(published_only: true).columns
      preload_cards(@columns)
      @shipped = recently_shipped
      fresh_when etag: [ *shiplog_etag_parts, etag_for(@columns) ]
    end

    private

    # The cards read each entry's issue, its repository (label) and its sub-issues (parts).
    def preload_cards(columns)
      entries = columns.values.flatten.map(&:entry)
      ActiveRecord::Associations::Preloader.new(records: entries, associations: { subject: [ :repository, :children ] }).call
    end

    def recently_shipped
      count = Shiplog.config.roadmap_shipped_count
      return Entry.none if count.zero?

      Entry.approved.where(kind: Entry::CHANGELOG_KINDS).where.not(released_on: nil)
        .order(released_on: :desc, approved_at: :desc, id: :desc).limit(count).load
    end

    def etag_for(columns)
      columns.transform_values { |items| items.map { |item| [ item.entry.id, item.entry.updated_at ] } }
    end
  end
end
