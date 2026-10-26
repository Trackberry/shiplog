require "nokogiri"

module Shiplog
  class ImageFetcher
    # Which images of a GitHub body (its rendered HTML) may be downloaded: <img src> URLs on GitHub's own image
    # hosts, https only, matched on the exact host (so user-images.githubusercontent.com.evil.com is out).
    module Sources
      HOSTS = %w[
        private-user-images.githubusercontent.com user-images.githubusercontent.com camo.githubusercontent.com
        raw.githubusercontent.com objects.githubusercontent.com
      ].freeze
      ATTACHMENTS_HOST = "github.com".freeze
      ATTACHMENTS_PATH = "/user-attachments/assets/".freeze

      # The allowed, distinct image URLs of the HTML, in document order, at most `limit`.
      def self.urls(html, limit:)
        Nokogiri::HTML.fragment(html.to_s).css("img[src]").filter_map { |img| parse(img["src"]) }
          .select { |uri| allowed?(uri) }.map(&:to_s).uniq.first(limit)
      end

      # Whether a URI may be requested: also checked on every redirect hop.
      def self.allowed?(uri)
        return false unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.port == 443

        host = uri.host.to_s.downcase
        return true if HOSTS.include?(host)

        host == ATTACHMENTS_HOST && uri.path.start_with?(ATTACHMENTS_PATH) && !uri.path.split("/").include?("..")
      end

      def self.parse(value)
        URI.parse(value.to_s.strip)
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
