module Shiplog
  class RefreshJob < ApplicationJob
    retry_on Github::Transient, attempts: 5, wait: :polynomially_longer

    def perform(repository_full_name, kind, number)
      configured_name = Shiplog.config.repository_configured?(repository_full_name)
      unless configured_name
        Rails.logger.info("[shiplog] Ignoring refresh for unconfigured repository #{repository_full_name}")
        return
      end

      repository = Repository.find_or_create_by!(full_name: configured_name)
      case kind.to_s
      when "issue" then import(repository, number, Github::Queries::ISSUE, "issue", Sync::IssueImporter)
      when "pull_request" then import(repository, number, Github::Queries::PULL_REQUEST, "pullRequest", Sync::PullRequestImporter)
      else raise ArgumentError, "Unknown kind: #{kind.inspect}"
      end
      Sync::UpgradeDetector.call_isolated(repository) if kind.to_s == "pull_request"
      Drafter.call
    end

    private

    def import(repository, number, query, field, importer)
      owner, name = repository.full_name.split("/", 2)
      node = Github::Client.new.query(query, { owner:, name:, number: }).dig("repository", field)
      importer.new(repository).import(node) if node
      close_deleted(repository, number, node) if field == "issue"
    end

    # Deleted issues come back as null; transferred ones may come back as a different node. Either way the local
    # row at this repository and number is gone from GitHub: close it, keeping the row and its entries for audit.
    def close_deleted(repository, number, node)
      Issue.where(repository:, number:).where.not(node_id: node&.fetch("id")).find_each do |issue|
        issue.update!(state: "closed", state_reason: "deleted", closed_at: issue.closed_at || Time.current)
      end
    end
  end
end
