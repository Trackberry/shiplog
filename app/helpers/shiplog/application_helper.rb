module Shiplog
  module ApplicationHelper
    GITHUB_URL_PREFIX = "https://github.com/".freeze

    # Links only to github.com over https; anything else (javascript:, data:, other hosts) renders as plain text.
    def shiplog_github_link(text, url)
      if url.to_s.start_with?(GITHUB_URL_PREFIX)
        link_to text, url, rel: "noopener noreferrer", target: "_blank"
      else
        text
      end
    end
  end
end
