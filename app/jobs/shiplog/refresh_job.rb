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
      Drafter.call
    end

    private

    def import(repository, number, query, field, importer)
      owner, name = repository.full_name.split("/", 2)
      node = Github::Client.new.query(query, { owner:, name:, number: }).dig("repository", field)
      importer.new(repository).import(node) if node
    end
  end
end
