module Shiplog
  module Sync
    class PullRequestImporter
      include NodeAttributes

      STATES = { "OPEN" => "open", "CLOSED" => "closed", "MERGED" => "merged" }.freeze

      def initialize(repository) = @repository = repository

      def import(node)
        with_race_retry do
          pull_request = PullRequest.find_by(node_id: node["id"])
          pull_request&.lock!
          pull_request ||= PullRequest.new(node_id: node["id"])
          next pull_request if stale?(pull_request, node)

          pull_request.assign_attributes(attributes_for(node))
          pull_request.save!
          replace_links(pull_request, node)
          pull_request
        end
      end

      private

      def attributes_for(node)
        {
          repository: repository_for(node),
          number: node["number"], title: node["title"], body: node["body"],
          state: STATES.fetch(node["state"]), merged_at: node["mergedAt"],
          author_login: author_login(node), labels: label_names(node),
          url: node["url"], github_updated_at: node["updatedAt"]
        }.merge(upgrade_inputs(node))
      end

      # What upgrade detection needs. Nested pull requests (from an issue's closing references) carry no
      # `files`, and must not erase what an earlier import stored.
      def upgrade_inputs(node)
        return {} unless node.key?("files")

        paths = nodes_of(node, "files").map { |file| file["path"] }
        # More files than one page: the lockfile may be on a later page, and the blob diff is the real check.
        { base_oid: base_oid(node), merge_oid: node.dig("mergeCommit", "oid"),
          lockfile_changed: paths.include?(Shiplog.config.lockfile_path) || !complete?(node, "files") }
      end

      # `baseRefOid` is the base tip as of the last update of the pull request, so upgrades merged since then
      # would show up as false diffs. The merge commit's first parent is the base at merge, for merge and squash
      # commits alike.
      def base_oid(node)
        node.dig("mergeCommit", "parents", "nodes", 0, "oid").presence || node["baseRefOid"]
      end

      def repository_for(node)
        full_name = node.dig("repository", "nameWithOwner")
        return @repository if full_name.blank?

        repository_named(full_name)
      end

      def replace_links(pull_request, node)
        return unless node.key?("closingIssuesReferences")

        issue_ids = nodes_of(node, "closingIssuesReferences").map { |issue| issue["id"] }
        if complete?(node, "closingIssuesReferences")
          IssueLink.where(pull_request_node_id: pull_request.node_id).where.not(issue_node_id: issue_ids).delete_all
        end
        insert_links(issue_ids.map { |id| { issue_node_id: id, pull_request_node_id: pull_request.node_id } })
      end
    end
  end
end
