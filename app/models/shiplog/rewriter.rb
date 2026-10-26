module Shiplog
  class Rewriter
    NOT_CUSTOMER_FACING = "Not customer-facing (suggested by AI)".freeze

    def initialize(entry)
      @entry = entry
    end

    def call(force: false)
      return @entry if @entry.approved? && !force

      result = parse(request)
      result ? apply(result) : fail_with("Could not parse rewriter output")
    rescue StandardError => error
      fail_with(error.message)
    end

    private
      def request
        rewriter = Shiplog.config.rewriter
        raise "No rewriter configured" unless rewriter

        rewriter.call(Prompt.new(@entry).to_s).to_s
      end

      def parse(reply)
        json = reply[/\{.*\}/m]
        data = json && JSON.parse(json)
        data if data.is_a?(Hash) && data["title"].is_a?(String) && data["title"].present?
      rescue JSON::ParserError
        nil
      end

      def apply(data)
        @entry.assign_attributes(title: data["title"], body: data["body"].to_s, rewritten_at: Time.current,
          rewrite_error: nil, source_digest: Entry.digest_for(@entry.subject))
        discard_if_not_customer_facing(data)
        @entry.save!
      end

      def discard_if_not_customer_facing(data)
        return unless data["customer_facing"] == false && @entry.change? && @entry.draft?

        @entry.assign_attributes(status: "discarded", discard_reason: NOT_CUSTOMER_FACING)
      end

      def fail_with(message)
        subject = @entry.subject
        @entry.title = subject.title if @entry.title.blank?
        @entry.body = subject.body if @entry.body.blank?
        @entry.source_digest ||= Entry.digest_for(subject)
        @entry.rewrite_error = message
        @entry.save!
      end
  end
end
