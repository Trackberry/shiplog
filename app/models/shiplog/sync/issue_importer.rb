module Shiplog
  module Sync
    class IssueImporter
      include NodeAttributes

      def initialize(repository) = @repository = repository

      def import(node)
        Issue.transaction do
          issue = Issue.find_or_initialize_by(node_id: node["id"])
          next issue if stale?(issue, node)

          issue.assign_attributes(attributes_for(node))
          issue.save!
          replace_links(issue, node)
          issue
        end
      end

      private

      def attributes_for(node)
        {
          repository: @repository,
          number: node["number"], title: node["title"], body: node["body"],
          state: node["state"].downcase, state_reason: node["stateReason"]&.downcase,
          labels: label_names(node), milestone_title: node.dig("milestone", "title"),
          assignees_count: node.dig("assignees", "totalCount").to_i,
          parent_node_id: node.dig("parent", "id"), url: node["url"],
          github_created_at: node["createdAt"], github_updated_at: node["updatedAt"],
          closed_at: node["closedAt"]
        }
      end

      def replace_links(issue, node)
        pull_requests = node.dig("closedByPullRequestsReferences", "nodes").to_a
        importer = PullRequestImporter.new(@repository)
        pull_requests.each { |pr| importer.import(pr) }
        ids = pull_requests.map { |pr| pr["id"] }
        IssueLink.where(issue_node_id: issue.node_id).where.not(pull_request_node_id: ids).delete_all
        ids.each { |id| IssueLink.find_or_create_by!(issue_node_id: issue.node_id, pull_request_node_id: id) }
      end
    end
  end
end
