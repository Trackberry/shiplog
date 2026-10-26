module Shiplog
  class Roadmap
    Item = Data.define(:issue, :entry, :column)

    def initialize(published_only: true) = @published_only = published_only

    def columns
      items.group_by(&:column).then { |grouped| Issue::COLUMNS.index_with { |column| grouped.fetch(column, []) } }
    end

    def items
      candidates = Issue.open.publicly_labeled.includes(:parent, :entries)
        .order(Issue.arel_table[:position].asc.nulls_last, Issue.arel_table[:github_updated_at].desc)
        .reject { |issue| issue.parent&.public? }
      children_index = Issue.children_index(candidates)
      open_pr_node_ids = open_pr_issue_node_ids(candidates, children_index)

      candidates.filter_map do |issue|
        entry = issue.entries.find(&:roadmap?)
        next if @published_only && !entry&.approved?
        column = ColumnResolver.new(issue, children_index:, open_pr_node_ids:).column
        Item.new(issue:, entry:, column:)
      end
    end

    private
      def open_pr_issue_node_ids(candidates, children_index)
        node_ids = candidates.map(&:node_id) + children_index.values.flatten.map(&:node_id)
        IssueLink.where(issue_node_id: node_ids.uniq)
          .joins(:pull_request).merge(PullRequest.where(state: "open"))
          .distinct.pluck(:issue_node_id).to_set
      end
  end
end
