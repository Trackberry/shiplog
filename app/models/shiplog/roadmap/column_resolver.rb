module Shiplog
  class Roadmap
    class ColumnResolver
      def initialize(issue) = @issue = issue

      def column
        @issue.pinned_column ||
          (in_progress? && "in_progress") ||
          (coming_soon? && "coming_soon") ||
          "later"
      end

      private
        def in_progress?
          @issue.assignees_count.positive? ||
            [ @issue, *@issue.descendants ].any? { |issue| issue.linked_pull_requests.any?(&:open?) }
        end

        def coming_soon?
          @issue.milestone_title.present? || @issue.labels.intersect?(Shiplog.config.soon_labels)
        end
    end
  end
end
