module Shiplog
  module Admin
    module EntriesHelper
      def source_title(subject)
        subject.is_a?(Commit) ? subject.message.lines.first.to_s.strip : subject.title
      end

      def source_body(subject)
        subject.is_a?(Commit) ? subject.message.lines.drop(1).join.strip : subject.body.to_s
      end

      def source_reference(subject)
        return subject.sha.first(7) if subject.is_a?(Commit)

        "#{subject.repository.full_name}##{subject.number}"
      end

      def entry_heading(entry)
        entry.title.presence || source_title(entry.subject)
      end

      # The URL of an image's thumbnail: a 200x200 variant when the host has image_processing, else the original
      # (the stylesheet sizes it).
      def image_thumbnail_path(image)
        source = Gem.loaded_specs.key?("image_processing") && image.variable? ? image.variant(resize_to_limit: [ 200, 200 ]) : image
        polymorphic_path(source)
      rescue ActionController::UrlGenerationError, NoMethodError, ArgumentError
        nil
      end

      # "Spanish (es)" for a locale of config.locales; the code alone when Shiplog has no name for the language.
      def translation_language_label(locale)
        name = Shiplog::Translator.language_name(locale)
        name == locale.to_s ? name : "#{name} (#{locale})"
      end

      def entries_filter_path(status: nil, kind: nil, page: nil)
        root_path({ status:, kind:, page: }.compact_blank)
      end
    end
  end
end
