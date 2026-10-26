module Shiplog
  class ScanChangesJob < ApplicationJob
    DEFAULT_WINDOW = 7.days

    # Where a repository's next scan starts, and so the oldest merge nothing will draft before: the end of the
    # last scan, or DEFAULT_WINDOW ago for a repository never scanned.
    def self.window_start(repository) = repository.changes_scanned_at || DEFAULT_WINDOW.ago

    def perform
      client = Github::Client.new
      Shiplog.config.repository_names.each do |full_name|
        scan(Repository.find_or_create_by!(full_name:), client)
      end
      Drafter.call
    end

    private
      def scan(repository, client)
        since = self.class.window_start(repository)
        started_at = Time.current
        # Import late-synced PRs first so anything merged before `started_at` is visible to the scan.
        Sync::RepositorySync.new(repository, client:).call
        if Shiplog.config.changelog_repository?(repository.full_name)
          Sync::CommitScanner.new(repository, client:).call(since:)
          draft_changes(ChangeCandidates.new(repository:, since:, before: started_at).to_a)
        end
        repository.update!(changes_scanned_at: window_end(repository, started_at, since))
      rescue Github::RateLimited
        raise
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { repository: repository.full_name })
      end

      # Pull requests of this window that await upgrade detection are held back by ChangeCandidates, so the window
      # stays at the oldest one and the next scan reconsiders it once it is checked. It never ends before `since`:
      # older pending pull requests are outside the window, and the window must not move backwards.
      def window_end(repository, started_at, since)
        oldest_pending = Shiplog.config.changelog_repository?(repository.full_name) ? ChangeCandidates.oldest_pending(repository, since:) : nil
        [ [ started_at, oldest_pending ].compact.min, since ].max
      end

      def draft_changes(candidates)
        candidates.each { |subject| Drafter.draft(subject, "change", released_on: released_on(subject)) }
      end

      def released_on(subject)
        (subject.is_a?(PullRequest) ? subject.merged_at : subject.committed_at).to_date
      end
  end
end
