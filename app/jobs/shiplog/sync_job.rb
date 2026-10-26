module Shiplog
  class SyncJob < ApplicationJob
    def perform
      client = Github::Client.new
      repositories = Shiplog.config.repositories.map { |full_name| Repository.find_or_create_by!(full_name:) }
      repositories.each { |repository| sync(repository, client) }
      Drafter.call
    end

    private

    def sync(repository, client)
      Sync::RepositorySync.new(repository, client:).call
    rescue Github::RateLimited
      raise
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { repository: repository.full_name })
    end
  end
end
