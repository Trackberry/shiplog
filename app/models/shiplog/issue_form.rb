module Shiplog
  module IssueForm
    NO_RESPONSE = "_No response_".freeze

    def self.parse(body)
      body.to_s.split(/^### +/).drop(1).to_h do |section|
        heading, content = section.split("\n", 2)
        [ heading.strip.downcase.tr(" ", "_"), content.to_s.strip.then { |text| text.empty? || text == NO_RESPONSE ? nil : text } ]
      end
    end
  end
end
