module Shiplog
  module Sync
    class CommitScanner
      def initialize(repository, client: Github::Client.new)
        @repository = repository
        @client = client
        @owner, @name = repository.full_name.split("/", 2)
      end

      def call(since:)
        after = nil
        loop do
          history = fetch(since:, after:)
          return unless history

          history["nodes"].each { |node| store(node) }
          return unless history.dig("pageInfo", "hasNextPage")

          after = history.dig("pageInfo", "endCursor")
        end
      end

      private

      def fetch(since:, after:)
        variables = { owner: @owner, name: @name, since: since&.iso8601, after: }
        @client.query(Github::Queries::COMMITS, variables).dig("repository", "defaultBranchRef", "target", "history")
      end

      def store(node)
        return unless node.dig("associatedPullRequests", "totalCount").zero?

        commit = Commit.find_or_initialize_by(repository: @repository, sha: node["oid"])
        commit.update!(message: node["message"], author_login: node.dig("author", "user", "login"),
          committed_at: node["committedDate"], url: node["url"])
      end
    end
  end
end
