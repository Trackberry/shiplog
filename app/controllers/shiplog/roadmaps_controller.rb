module Shiplog
  class RoadmapsController < PublicController
    def show
      @columns = Roadmap.new(published_only: true).columns
      fresh_when etag: [ I18n.locale, etag_for(@columns) ]
    end

    private

    def etag_for(columns)
      columns.transform_values { |items| items.map { |item| [ item.entry.id, item.entry.updated_at ] } }
    end
  end
end
