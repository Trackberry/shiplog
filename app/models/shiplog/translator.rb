module Shiplog
  # Translates an approved entry's title and body into one locale with config.rewriter and stores the result in
  # an EntryTranslation, which is published with the English text (no second approval).
  #
  #   Translator.new(entry, :es).call               # translates unless a translation of this English text exists
  #   Translator.new(entry, :es).call(force: true)  # always, also over an admin's edit
  #
  # The English text is what the digest covers (Entry#translation_source_digest). A translation made from the
  # current text is left alone, which includes an admin's edit; a translation made from older text is replaced,
  # the admin's edit too (it is logged).
  class Translator
    class InvalidReply < StandardError; end

    LANGUAGES = {
      ar: "Arabic", bg: "Bulgarian", ca: "Catalan", cs: "Czech", da: "Danish", de: "German", el: "Greek", en: "English",
      es: "Spanish", et: "Estonian", fi: "Finnish", fr: "French", he: "Hebrew", hi: "Hindi", hr: "Croatian", hu: "Hungarian",
      id: "Indonesian", it: "Italian", ja: "Japanese", ko: "Korean", lt: "Lithuanian", lv: "Latvian", nb: "Norwegian",
      nl: "Dutch", no: "Norwegian", pl: "Polish", pt: "Portuguese", "pt-BR": "Brazilian Portuguese", ro: "Romanian",
      ru: "Russian", sk: "Slovak", sl: "Slovenian", sr: "Serbian", sv: "Swedish", th: "Thai", tr: "Turkish",
      uk: "Ukrainian", vi: "Vietnamese", zh: "Chinese", "zh-CN": "Simplified Chinese", "zh-TW": "Traditional Chinese"
    }.freeze

    # The language to name in the prompt for a locale code, or the code itself when it is not in LANGUAGES.
    def self.language_name(locale) = LANGUAGES.fetch(locale.to_s.to_sym, locale.to_s)

    def initialize(entry, locale)
      @entry = entry
      @locale = locale.to_s
    end

    # Returns the stored translation, or nil when nothing was written: the entry is not approved, the locale is not
    # configured, there is no rewriter, or the translation is current already. Raises InvalidReply (or whatever
    # the rewriter raises) when the reply is unusable, which includes a blank body for an entry that has one;
    # the job retries.
    def call(force: false)
      return unless Entry.translated_locale?(@locale) && Shiplog.config.rewriter && @entry.approved?

      digest = @entry.translation_source_digest
      return if !force && current?(@entry.translations.find_by(locale: @locale), digest)

      result = parse(request)
      raise InvalidReply, "Could not parse the translation into #{@locale}" unless result

      store(result, digest, force:)
    end

    private
      def current?(translation, digest) = translation&.source_digest == digest

      def request
        Shiplog.config.rewriter.call(Prompt.new(@entry, @locale).to_s).to_s
      end

      def parse(reply)
        Rewriter.first_valid_object(reply) { |data| validate(data) }
      end

      def validate(data)
        title, body = data.values_at("title", "body")
        return unless title.is_a?(String) && (body.nil? || body.is_a?(String))

        title = Rewriter.sanitize(title).squish.truncate(Rewriter::MAX_TITLE_CHARS, separator: " ", omission: "…")
        return if title.blank?

        body = limit_body(Rewriter.sanitize(body.to_s).strip)
        return if body.blank? && @entry.body.present? # a blank body would be published in place of the English text

        { title:, body: }
      end

      def limit_body(body)
        return Rewriter.shorten_roadmap(body) if @entry.roadmap?

        body.truncate(Rewriter::MAX_BODY_CHARS, separator: " ", omission: "…")
      end

      # Writes under the entry's row lock, after checking again: the entry may have been unpublished, edited or
      # translated by an admin while the LLM was working. Text that changed meanwhile enqueues its own translation.
      def store(result, digest, force:)
        @entry.with_lock do
          @entry.reload
          next unless @entry.approved? && @entry.translation_source_digest == digest

          existing = @entry.translations.find_by(locale: @locale)
          next if !force && current?(existing, digest)

          log_replaced_edit(existing) if existing&.edited_by_admin
          (existing || @entry.translations.build(locale: @locale)).tap do |translation|
            translation.update!(title: result[:title], body: result[:body], source_digest: digest, edited_by_admin: false)
          end
        end
      end

      def log_replaced_edit(translation)
        Rails.logger.info("[shiplog] Replaced the admin-edited #{@locale} translation of entry #{@entry.id}: " \
          "#{translation.source_digest == @entry.translation_source_digest ? "retranslated on request" : "the English text changed"}")
      end
  end
end
