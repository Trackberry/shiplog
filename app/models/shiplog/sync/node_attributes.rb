module Shiplog
  module Sync
    module NodeAttributes
      private

      # GitHub returns null entries for items the token cannot access.
      def nodes_of(node, *path) = node.dig(*path, "nodes").to_a.compact

      # False when the connection reports more pages than were fetched.
      def complete?(node, *path) = !node.dig(*path, "pageInfo", "hasNextPage")

      def label_names(node) = nodes_of(node, "labels").map { |label| label["name"] }

      # GraphQL reports bots as "dependabot"; REST (and excluded_authors) say "dependabot[bot]".
      def author_login(node)
        login = node.dig("author", "login")
        node.dig("author", "__typename") == "Bot" && login ? "#{login}[bot]" : login
      end

      # Finds or builds the record of a GraphQL node and saves it from attributes_for(node), then replace_links, in a
      # race-safe transaction. A record already updated later than the node (a stale payload) is returned untouched.
      def import_record(model, node)
        with_race_retry do
          record = model.find_by(node_id: node["id"])
          record&.lock!
          record ||= model.new(node_id: node["id"])
          next record if stale?(record, node)

          record.assign_attributes(attributes_for(node))
          record.save!
          replace_links(record, node)
          record
        end
      end

      def stale?(record, node)
        record.persisted? && record.github_updated_at && record.github_updated_at > Time.iso8601(node["updatedAt"])
      end

      # Runs the block in a savepoint-backed transaction and retries once when a
      # concurrent writer wins the unique-index race.
      def with_race_retry
        attempts = 0
        begin
          attempts += 1
          ActiveRecord::Base.transaction(requires_new: true) { yield }
        rescue ActiveRecord::RecordNotUnique
          retry if attempts < 2
          raise
        end
      end

      def insert_links(rows)
        return if rows.empty?

        IssueLink.insert_all(rows, unique_by: %i[issue_node_id pull_request_node_id])
      end

      def repository_named(full_name)
        repositories[full_name] ||= Repository.find_by(full_name:) || Repository.create_or_find_by!(full_name:)
      end

      def repositories = (@repositories ||= { @repository.full_name => @repository })
    end
  end
end
