module Shiplog
  class ChangeCandidates
    COMMIT_TYPE = /\A(\w+)(\([^)]*\))?!?:/
    # The Conventional Commits types; "Importers: ..." is a topic prefix, not a type.
    CONVENTIONAL_TYPES = %w[feat fix perf refactor chore docs test ci build style revert deps].freeze

    def initialize(repository:, since:, before:)
      @repository = repository
      @window = since...before
    end

    def to_a
      pull_requests + commits
    end

    private
      def pull_requests
        candidates = @repository.pull_requests.where(state: "merged", merged_at: @window).where.missing(:entries).to_a
          .reject { |pull_request| excluded_label?(pull_request) || excluded_type?(pull_request) || Shiplog.config.excluded_author?(pull_request.author_login) }
        public_ids = pull_request_ids_in_public_tree(candidates)
        candidates.reject { |pull_request| public_ids.include?(pull_request.node_id) }
      end

      def commits
        @repository.commits.where(committed_at: @window).where.missing(:entries).order(:committed_at).to_a
          .select { |commit| eligible_commit?(commit) }
      end

      def excluded_label?(pull_request)
        pull_request.labels.intersect?(Shiplog.config.excluded_labels)
      end

      # Untyped PR titles stay in; the rewriter decides whether customers would notice.
      def excluded_type?(pull_request)
        type = pull_request.title[COMMIT_TYPE, 1]&.downcase
        CONVENTIONAL_TYPES.include?(type) && !Shiplog.config.commit_types.include?(type)
      end

      def eligible_commit?(commit)
        type = commit.title[COMMIT_TYPE, 1]
        type && Shiplog.config.commit_types.include?(type) && !Shiplog.config.excluded_author?(commit.author_login)
      end

      # Node ids of the pull requests linked to an issue that is public or has a public ancestor.
      # One query for the links, one for the linked issues, then one per ancestor level.
      def pull_request_ids_in_public_tree(pull_requests)
        return Set.new if pull_requests.empty?

        links = IssueLink.where(pull_request_node_id: pull_requests.map(&:node_id)).pluck(:issue_node_id, :pull_request_node_id)
        public_issue_ids = public_tree_issue_ids(links.map(&:first).uniq)
        links.filter_map { |issue_id, pull_request_id| pull_request_id if public_issue_ids.include?(issue_id) }.to_set
      end

      def public_tree_issue_ids(issue_ids)
        public_ids = Set.new
        current = Issue.where(node_id: issue_ids).index_by(&:node_id) # origin node_id => issue at the current level
        seen = current.transform_values { |issue| Set[issue.node_id] }

        (Issue::MAX_DEPTH + 1).times do
          break if current.empty?

          current.each { |origin, issue| public_ids << origin if issue.public? }
          current = climb(current.reject { |origin, _| public_ids.include?(origin) }, seen)
        end
        public_ids
      end

      def climb(current, seen)
        parent_ids = current.values.filter_map(&:parent_node_id).uniq
        return {} if parent_ids.empty?

        parents = Issue.where(node_id: parent_ids).index_by(&:node_id)
        current.each_with_object({}) do |(origin, issue), next_level|
          parent = parents[issue.parent_node_id]
          next_level[origin] = parent if parent && seen[origin].add?(parent.node_id)
        end
      end
  end
end
