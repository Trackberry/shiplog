module Shiplog
  class Rewriter
    NOT_CUSTOMER_FACING = "Not customer-facing (suggested by AI)".freeze
    PARSE_ERROR = "Could not parse rewriter output".freeze
    MAX_TITLE_CHARS = 120
    MAX_BODY_CHARS = 2_000
    MAX_ROADMAP_BODY_CHARS = 220
    # A period after a common abbreviation ("e.g.", "i.e.", "approx.", "etc.") does not end a sentence.
    SENTENCE_END = /(?<!\be\.g)(?<!\bi\.e)(?<!\bapprox)(?<!\betc)(?<!\bvs)(?<!\bcf)[.!?](?=\s|\z)/i

    # Balanced, string-aware {...} candidates (recursion via \g<0>).
    JSON_OBJECT = /\{(?:[^{}"]++|"(?:\\.|[^"\\])*+"|\g<0>)*+\}/m
    CONTROL_CHARS = /[\p{Cc}&&[^\n]]/

    def initialize(entry)
      @entry = entry
    end

    # Always returns the entry. A non-forced call never modifies an approved entry; a forced
    # call replaces the text of an approved entry but returns it to draft for re-approval.
    def call(force: false)
      return @entry if @entry.approved? && !force

      result = parse(request)
      locked(force) { result ? apply(result) : fail_with(PARSE_ERROR) }
      @entry
    rescue StandardError => error
      locked(force) { fail_with(error.message) }
      @entry
    end

    private
      # Re-checks state under a row lock: the entry may have been approved or edited during the LLM call.
      def locked(force)
        @entry.with_lock do
          @entry.reload
          yield unless @entry.approved? && !force
        end
      end

      def request
        rewriter = Shiplog.config.rewriter
        raise "No rewriter configured" unless rewriter

        rewriter.call(Prompt.new(@entry).to_s).to_s
      end

      def parse(reply)
        reply.scan(JSON_OBJECT).each do |candidate|
          data = JSON.parse(candidate)
          result = validate(data) if data.is_a?(Hash)
          return result if result
        rescue JSON::ParserError
          next
        end
        nil
      end

      def validate(data)
        title, body, customer_facing = data.values_at("title", "body", "customer_facing")
        customer_facing = true if customer_facing.nil?
        return unless title.is_a?(String) && (body.nil? || body.is_a?(String)) && [ true, false ].include?(customer_facing)

        title = sanitize(title).squish.truncate(MAX_TITLE_CHARS, separator: " ", omission: "…")
        return if title.blank?

        { title:, body: limit_body(sanitize(body.to_s).strip), customer_facing:, area: data["area"].then { |area| area.squish.presence if area.is_a?(String) } }
      end

      def limit_body(body)
        return body.truncate(MAX_BODY_CHARS, separator: " ", omission: "…") unless @entry.roadmap?

        shorten_roadmap(body)
      end

      # Roadmap bodies are two short sentences: cut after the last sentence that fits, else at a word.
      def shorten_roadmap(body)
        return body if body.length <= MAX_ROADMAP_BODY_CHARS

        last_end = body.enum_for(:scan, SENTENCE_END).map { Regexp.last_match.begin(0) }.select { |i| i < MAX_ROADMAP_BODY_CHARS }.last
        return body[0..last_end] if last_end

        body.truncate(MAX_ROADMAP_BODY_CHARS, separator: " ", omission: "…")
      end

      def sanitize(text)
        text.tr("\t", " ").gsub(CONTROL_CHARS, "")
      end

      def apply(result)
        discard = result[:customer_facing] == false && @entry.change? && @entry.draft?
        @entry.assign_attributes(title: result[:title], body: result[:body], rewritten_at: Time.current,
          rewrite_error: nil, source_digest: Entry.digest_for(@entry.subject))
        @entry.assign_attributes(status: "draft", approved_at: nil, approved_by: nil) if @entry.approved?
        @entry.assign_attributes(status: "discarded", discard_reason: NOT_CUSTOMER_FACING) if discard
        assign_area(result[:area]) unless discard
        @entry.save!
      end

      # A name the reply gave: an existing area, or a new one while below config.max_areas. A name that resolves to
      # nothing (cap reached, invalid) keeps the entry's current area: only an explicit valid name changes it. No
      # area in the reply keeps it too, and one an admin chose is never changed.
      def assign_area(name)
        return if name.nil? || @entry.area_set_by_admin?

        area = Area.resolve_or_create(name)
        @entry.area = area if area
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
