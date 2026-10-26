module Shiplog
  module Github
    class Error < StandardError; end

    class RateLimited < Error
      attr_reader :reset_at

      def initialize(reset_at)
        @reset_at = reset_at
        super("GitHub rate limit exceeded, resets at #{reset_at.utc.iso8601}")
      end
    end
  end
end
