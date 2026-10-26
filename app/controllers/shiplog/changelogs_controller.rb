module Shiplog
  class ChangelogsController < PublicController
    PER_PAGE = 30
    MAX_PAGE = 100_000
    MIN_FILTER_AREAS = 2

    before_action :set_area, only: :show

    def show
      @page = page_number
      scope = Entry.published_changelog.newest_first
      @query = search_query
      scope = scope.search(@query) if @query
      scope = scope.where(area_id: @area.id) if @area
      @areas = filter_areas
      records = scope.includes(:area).offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      return head(:not_found) if @page > 1 && records.empty?

      notify_changelog_seen
      @older = records.size > PER_PAGE
      @months = records.first(PER_PAGE).group_by { |entry| entry.released_on.beginning_of_month }
      @result_count = scope.count if @query
      fresh_when etag: [ *shiplog_etag_parts, *shiplog_area_etag_parts, @areas.map(&:id), @query, @page, @older,
        @months.values.flatten.map { |entry| [ entry.id, entry.updated_at, entry.area_id ] } ]
    end

    private

    # The areas to offer as filter links: those with published entries, in the admin's order, and only when there
    # are at least two (a single area filters nothing).
    def filter_areas
      areas = Area.ordered.where(id: Entry.published_changelog.where.not(area_id: nil).select(:area_id)).to_a
      areas.size >= MIN_FILTER_AREAS ? areas : []
    end

    # The normalised search query (words joined by one space), or nil when search is off or the query is blank.
    def search_query
      return unless Shiplog.config.changelog_search && params[:q].is_a?(String)

      Entry.search_terms(params[:q]).join(" ").presence
    end

    def page_number
      Integer(params[:page].to_s, 10, exception: false).to_i.clamp(1, MAX_PAGE)
    end
  end
end
