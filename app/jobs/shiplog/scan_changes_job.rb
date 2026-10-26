module Shiplog
  class ScanChangesJob < ApplicationJob
    DEFAULT_WINDOW = 7.days

    def perform
      client = Github::Client.new
      Shiplog.config.repository_names.each do |full_name|
        scan(Repository.find_or_create_by!(full_name:), client)
      end
      Drafter.call
    end

    private
      def scan(repository, client)
        since = repository.changes_scanned_at || DEFAULT_WINDOW.ago
        started_at = Time.current
        # Import late-synced PRs first so anything merged before `started_at` is visible to the scan.
        Sync::RepositorySync.new(repository, client:).call
        if Shiplog.config.changelog_repository?(repository.full_name)
          Sync::CommitScanner.new(repository, client:).call(since:)
          draft_changes(ChangeCandidates.new(repository:, since:, before: started_at).to_a)
        end
        repository.update!(changes_scanned_at: started_at)
      rescue Github::RateLimited
        raise
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { repository: repository.full_name })
      end

      def draft_changes(candidates)
        candidates.each { |subject| Drafter.draft(subject, "change", released_on: released_on(subject)) }
      end

      def released_on(subject)
        (subject.is_a?(PullRequest) ? subject.merged_at : subject.committed_at).to_date
      end
  end
end
