module Shiplog
  class Roadmap
    Item = Data.define(:issue, :entry, :column)

    def initialize(published_only: true) = @published_only = published_only

    def columns
      items.group_by(&:column).then { |grouped| Issue::COLUMNS.index_with { |column| grouped.fetch(column, []) } }
    end

    def items
      issues = Issue.open.publicly_labeled.includes(:parent, :entries)
        .order(Arel.sql("position ASC NULLS LAST, github_updated_at DESC"))
      issues.reject { |issue| issue.parent&.public? }.filter_map do |issue|
        entry = issue.entries.find(&:roadmap?)
        next if @published_only && !entry&.approved?
        Item.new(issue:, entry:, column: ColumnResolver.new(issue).column)
      end
    end
  end
end
