module Shiplog
  module Sync
    module NodeAttributes
      private

      def label_names(node) = node.dig("labels", "nodes").to_a.map { |label| label["name"] }

      def stale?(record, node)
        record.persisted? && record.github_updated_at && record.github_updated_at > Time.iso8601(node["updatedAt"])
      end
    end
  end
end
