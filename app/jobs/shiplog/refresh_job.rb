module Shiplog
  class RefreshJob < ApplicationJob
    def perform(repository_full_name, kind, number)
      repository = Repository.find_or_create_by!(full_name: repository_full_name)
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
