module Shiplog
  class ChangeCandidates
    COMMIT_TYPE = /\A(\w+)(\([^)]*\))?!?:/
    # The Conventional Commits types; "Importers: ..." is a topic prefix, not a type.
    CONVENTIONAL_TYPES = %w[feat fix perf refactor chore docs test ci build style revert deps].freeze

    # Dropped from the upgrade bypass: the label Dependabot adds. Any other excluded label still excludes.
    UPGRADE_LABEL = "dependencies".freeze

    # The merge time of the oldest merged pull request merged at or after `since` whose upgrade detection has not
    # run yet, or nil. Such pull requests are held back from candidates, so a scan window must not move past it.
    # Older ones are outside the window: they are never drafted, and must not drag it backwards. Nil when no gem
    # is tracked, since detection would never run.
    def self.oldest_pending(repository, since:)
      return unless Shiplog.config.tracked_gems.any?

      repository.pull_requests.awaiting_upgrade_check.where(merged_at: since..).reorder(:merged_at).pick(:merged_at)
    end

    def initialize(repository:, since:, before:)
      @repository = repository
      @window = since...before
    end

    def to_a
      pull_requests + commits
    end

    private
      def pull_requests
        candidates = merged_in_window.where.missing(:entries).to_a
        upgrade_ids = ids_with_upgrades(candidates)
        candidates = candidates.reject do |pull_request|
          if upgrade_ids.include?(pull_request.id)
            excluded_label?(pull_request, ignoring: UPGRADE_LABEL)
          else
            excluded_label?(pull_request) || excluded_type?(pull_request) || Shiplog.config.excluded_author?(pull_request.author_login)
          end
        end
        public_ids = pull_request_ids_in_public_tree(candidates)
        candidates.reject { |pull_request| public_ids.include?(pull_request.node_id) }
      end

      # Pull requests still awaiting upgrade detection are held back (neither candidates nor excluded): excluding
      # them now would skip an upgrade for good once the window moves on.
      def merged_in_window
        scope = @repository.pull_requests.where(state: "merged", merged_at: @window)
        Shiplog.config.tracked_gems.any? ? scope.where.not(id: @repository.pull_requests.awaiting_upgrade_check.reorder(nil).select(:id)) : scope
      end

      # A pull request that upgrades a tracked gem with customer-visible changes is how customers receive them,
      # so a Dependabot author, a chore(deps) title or a dependencies label does not exclude it. Other excluded
      # labels, such as an `internal` a human added, still do.
      def ids_with_upgrades(pull_requests)
        PullRequestUpgrade.where(pull_request_id: pull_requests.map(&:id)).where("jsonb_array_length(gem_changes) > 0")
          .distinct.pluck(:pull_request_id).to_set
      end

      def commits
        @repository.commits.where(committed_at: @window).where.missing(:entries).order(:committed_at).to_a
          .select { |commit| eligible_commit?(commit) }
      end

      def excluded_label?(pull_request, ignoring: nil)
        pull_request.labels.intersect?(Shiplog.config.excluded_labels - Array(ignoring))
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
