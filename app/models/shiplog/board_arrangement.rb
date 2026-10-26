module Shiplog
  class BoardArrangement
    def self.unpin!(issue)
      issue.update!(pinned_column: nil, position: nil)
    end

    # Pins only the moved card to the column; every id in issue_ids (the full visible order of the column) gets a position.
    def initialize(column:, moved_id:, issue_ids:)
      @column = column.to_s
      @moved_id = Integer(moved_id.to_s, 10)
      @issue_ids = Array(issue_ids).map { |id| Integer(id.to_s, 10) }.uniq
    end

    def save!
      raise ArgumentError, "Unknown column: #{@column.inspect}" unless Issue::COLUMNS.include?(@column)
      raise ArgumentError, "moved_id must be one of issue_ids" unless @issue_ids.include?(@moved_id)

      Issue.transaction do
        issues = Issue.where(id: roadmap_issue_ids & @issue_ids).index_by(&:id)
        missing = @issue_ids - issues.keys
        raise ActiveRecord::RecordNotFound, "Not roadmap items: #{missing.join(", ")}" if missing.any?

        @issue_ids.each_with_index do |id, position|
          issue = issues.fetch(id)
          issue.pinned_column = @column if id == @moved_id
          issue.position = position
          issue.save!
        end
      end
    end

    private

    def roadmap_issue_ids
      Roadmap.new(published_only: false).items.map { |item| item.issue.id }
    end
  end
end
