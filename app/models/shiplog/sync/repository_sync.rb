module Shiplog
  module Sync
    class RepositorySync
      def initialize(repository, client: Github::Client.new)
        @repository = repository
        @client = client
        @owner, @name = repository.full_name.split("/", 2)
        @cursor = repository.sync_cursor
        @newest = nil
      end

      # How far behind the newest-seen timestamp the stored cursor is kept, to absorb clock skew.
      CURSOR_SAFETY_WINDOW = 5.minutes

      def call
        @started_at = Time.current
        sync_issues
        sync_pull_requests
        @repository.update!(sync_cursor: next_cursor, synced_at: Time.current, last_error: nil)
        # After the cursor: a detector failure must not keep the cursor from moving.
        UpgradeDetector.call_isolated(@repository, client: @client)
      rescue StandardError => error
        @repository.update!(last_error: error.message)
        raise
      end

      private

      def sync_issues
        importer = IssueImporter.new(@repository)
        each_page(Github::Queries::ISSUES, "issues", since: @cursor&.iso8601(6)) do |nodes|
          nodes.each do |node|
            next if node["__typename"] == "PullRequest"

            importer.import(node)
            track(node)
          end
          :continue
        end
      end

      def sync_pull_requests
        importer = PullRequestImporter.new(@repository)
        each_page(Github::Queries::PULL_REQUESTS, "pullRequests") do |nodes|
          fresh = nodes.take_while { |node| @cursor.nil? || Time.iso8601(node["updatedAt"]) >= @cursor }
          fresh.each do |node|
            importer.import(node)
            track(node)
          end
          fresh.size == nodes.size ? :continue : :stop
        end
      end

      def each_page(query, field, **variables)
        after = nil
        loop do
          connection = @client.query(query, { owner: @owner, name: @name, after:, **variables }).dig("repository", field)
          break if yield(connection["nodes"].to_a.compact) == :stop
          break unless connection.dig("pageInfo", "hasNextPage")

          after = connection.dig("pageInfo", "endCursor")
        end
      end

      # The issue and PR phases share one cursor, so an issue updated while the PR
      # phase runs could be newer than nothing we saw. Never advance past the sync
      # start, and keep a safety window for clock skew. `since` is inclusive and the
      # stale guard prevents regressions, so re-importing is harmless.
      def next_cursor
        return @cursor if @newest.nil?

        candidate = [ @newest, @started_at ].min - CURSOR_SAFETY_WINDOW
        @cursor && @cursor > candidate ? @cursor : candidate
      end

      def track(node)
        updated_at = Time.iso8601(node["updatedAt"])
        @newest = updated_at if @newest.nil? || updated_at > @newest
      end
    end
  end
end
