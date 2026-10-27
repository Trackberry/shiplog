module Shiplog
  module Newsletter
    # The admin's CSV export of subscribers, written by hand: the csv gem is no longer a default gem and Shiplog
    # adds no dependency for a few lines. Every cell is quoted, and a cell that a spreadsheet would read as a
    # formula (starting with =, +, -, @, a tab or a carriage return) gets a leading apostrophe, so an address
    # like "=HYPERLINK(...)@evil.example" cannot run anything when the file is opened.
    module Csv
      HEADERS = %w[email locale status source subscribed_at confirmed_at unsubscribed_at].freeze
      FORMULA = /\A[=+\-@\t\r]/

      # The CSV text of a scope of subscribers, read in batches.
      def self.generate(scope)
        lines = [ line(HEADERS) ]
        scope.find_each { |subscriber| lines << line(row(subscriber)) }
        lines.join("\n") + "\n"
      end

      def self.row(subscriber)
        [ subscriber.email, subscriber.locale, subscriber.status, subscriber.source,
          *[ subscriber.created_at, subscriber.confirmed_at, subscriber.unsubscribed_at ].map { |time| time&.utc&.iso8601 } ]
      end

      def self.line(values) = values.map { |value| cell(value) }.join(",")

      def self.cell(value)
        text = value.to_s
        text = "'#{text}" if FORMULA.match?(text)
        %("#{text.gsub('"', '""')}")
      end
    end
  end
end
