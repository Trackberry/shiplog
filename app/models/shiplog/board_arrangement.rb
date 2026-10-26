module Shiplog
  class BoardArrangement
    def self.unpin!(issue)
      issue.update!(pinned_column: nil, position: nil)
    end

    def initialize(column:, issue_ids:)
      @column = column.to_s
      @issue_ids = Array(issue_ids).map { |id| Integer(id.to_s, 10) }.uniq
    end

    def save!
      raise ArgumentError, "Unknown column: #{@column.inspect}" unless Issue::COLUMNS.include?(@column)

      issues = Issue.where(id: roadmap_issue_ids & @issue_ids).index_by(&:id)
      missing = @issue_ids - issues.keys
      raise ActiveRecord::RecordNotFound, "Not roadmap items: #{missing.join(", ")}" if missing.any?

      Issue.transaction do
        @issue_ids.each_with_index { |id, position| issues.fetch(id).update!(pinned_column: @column, position:) }
      end
    end

    private

    def roadmap_issue_ids
      Roadmap.new(published_only: false).items.map { |item| item.issue.id }
    end
  end
end
