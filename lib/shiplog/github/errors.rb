module Shiplog
  module Github
    class Error < StandardError; end

    # Network failures and 5xx responses; safe to retry later.
    class Transient < Error; end

    # HTTP 404: the resource does not exist, or the token cannot see it.
    class NotFound < Error; end

    class RateLimited < Error
      attr_reader :reset_at

      def initialize(reset_at)
        @reset_at = reset_at
        super("GitHub rate limit exceeded, resets at #{reset_at.utc.iso8601}")
      end
    end
  end
end
