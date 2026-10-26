module Shiplog
  class ChangelogsController < PublicController
    PER_PAGE = 30
    MAX_PAGE = 100_000

    def show
      @page = page_number
      scope = Entry.approved.where(kind: %w[feature change]).where.not(released_on: nil)
        .order(released_on: :desc, approved_at: :desc, id: :desc)
      records = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @older = records.size > PER_PAGE
      @months = records.first(PER_PAGE).group_by { |entry| entry.released_on.beginning_of_month }
      fresh_when etag: [ @page, @older, @months.values.flatten.map { |entry| [ entry.id, entry.updated_at ] } ]
    end

    private

    def page_number
      Integer(params[:page].to_s, 10, exception: false).to_i.clamp(1, MAX_PAGE)
    end
  end
end
