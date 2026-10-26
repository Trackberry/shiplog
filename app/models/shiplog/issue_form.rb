module Shiplog
  module IssueForm
    NO_RESPONSE = "_No response_".freeze
    HEADING = /\A### +(.*)/
    FENCE = /\A {0,3}(`{3,}|~{3,})/

    # Splits an issue-form body into sections keyed by their `### ` headings.
    # Headings inside fenced code blocks are content, not section boundaries.
    def self.parse(body)
      sections = {}
      current = nil
      fence = nil

      body.to_s.each_line do |line|
        marker = line[FENCE, 1]
        fence = next_fence(fence, marker)
        heading = fence.nil? && marker.nil? ? line[HEADING, 1] : nil

        if heading
          current = sections_key(heading)
          sections[current] = +"" if current
        elsif current
          sections[current] << line
        end
      end

      sections.transform_values { |text| text.strip.then { |value| value.empty? || value == NO_RESPONSE ? nil : value } }
    end

    def self.next_fence(fence, marker)
      return fence unless marker
      return marker if fence.nil?

      marker[0] == fence[0] && marker.length >= fence.length ? nil : fence
    end

    def self.sections_key(heading)
      heading.strip.parameterize(separator: "_").presence
    end

    private_class_method :next_fence, :sections_key
  end
end
