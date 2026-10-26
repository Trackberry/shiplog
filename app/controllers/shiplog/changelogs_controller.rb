module Shiplog
  class ChangelogsController < PublicController
    PER_PAGE = 30
    MAX_PAGE = 100_000

    after_action :notify_changelog_seen, only: :show

    def show
      @page = page_number
      scope = Entry.published_changelog.newest_first
      @query = search_query
      scope = scope.search(@query) if @query
      records = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      return head(:not_found) if @page > 1 && records.empty?

      records.each(&:ensure_slug!) # entries approved before 0.3.0 get their permalink on first listing
      @older = records.size > PER_PAGE
      @months = records.first(PER_PAGE).group_by { |entry| entry.released_on.beginning_of_month }
      @result_count = scope.count if @query
      fresh_when etag: [ *shiplog_etag_parts, @query, @page, @older, @months.values.flatten.map { |entry| [ entry.id, entry.updated_at ] } ]
    end

    private

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
