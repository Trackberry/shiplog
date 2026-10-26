module Shiplog
  class Roadmap
    class ColumnResolver
      # With no precomputed data (single issue use), queries are issued on demand.
      # Roadmap passes a children index (parent node_id => children) and the set
      # of issue node_ids having an open linked PR so no per-issue queries run.
      def initialize(issue, children_index: nil, open_pr_node_ids: nil)
        @issue = issue
        @children_index = children_index
        @open_pr_node_ids = open_pr_node_ids
      end

      def column
        @issue.pinned_column ||
          (in_progress? && "in_progress") ||
          (coming_soon? && "coming_soon") ||
          "later"
      end

      private
        def in_progress?
          @issue.assignees_count.positive? || open_pr?
        end

        def open_pr?
          tree = [ @issue, *descendants ]
          if @open_pr_node_ids
            tree.any? { |issue| @open_pr_node_ids.include?(issue.node_id) }
          else
            IssueLink.where(issue_node_id: tree.map(&:node_id))
              .joins(:pull_request).merge(PullRequest.where(state: "open")).exists?
          end
        end

        def descendants
          return @issue.descendants unless @children_index

          Issue.descendants_in(@children_index, @issue)
        end

        def coming_soon?
          @issue.milestone_title.present? || @issue.labels.intersect?(Shiplog.config.soon_labels)
        end
    end
  end
end
