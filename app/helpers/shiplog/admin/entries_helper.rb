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

      def entries_filter_path(status: nil, kind: nil, page: nil)
        root_path({ status:, kind:, page: }.compact_blank)
      end
    end
  end
end
