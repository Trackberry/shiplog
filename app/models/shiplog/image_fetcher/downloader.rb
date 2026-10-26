require "net/http"

module Shiplog
  class ImageFetcher
    # Downloads one allowed image URL: five seconds to connect and five to read, at most three redirects (each
    # hop is checked against the allowlist again), at most 5 MB (counted while streaming, the download stops
    # past it). The GitHub token is sent to github.com only, never to another host. Returns a Download, or nil
    # (logged) when anything goes wrong or the bytes aren't a PNG, JPEG, GIF or WebP
    # of at most 10,000 pixels a side and 40 megapixels (see ImageType).
    class Downloader
      TIMEOUT = 5
      MAX_REDIRECTS = 3
      Download = Data.define(:body, :content_type, :width, :height)
      Rejected = Class.new(StandardError)

      def initialize(token: nil)
        @token = token
      end

      def call(url)
        body = fetch(Sources.parse(url), MAX_REDIRECTS)
        info = ImageType.analyze(body) # type by magic bytes, size from the header, both limits enforced

        Download.new(body:, content_type: info.content_type, width: info.width, height: info.height)
      rescue StandardError => error
        Rails.logger&.warn("[shiplog] Skipped image #{safe(url)}: #{error.class}: #{error.message}")
        nil
      end

      private

      def fetch(uri, redirects_left)
        raise Rejected, "host or scheme not allowed" unless uri && Sources.allowed?(uri)

        body = +"".b
        location = nil
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT
        http.request(build_request(uri)) do |response|
          case response
          when Net::HTTPSuccess then body = read(response)
          when Net::HTTPRedirection then location = response["location"].to_s
          else raise Rejected, "HTTP #{response.code}"
          end
        end
        return body unless location

        raise Rejected, "too many redirects" if redirects_left.zero?

        fetch(Sources.parse(URI.join(uri.to_s, location).to_s), redirects_left - 1)
      end

      def read(response)
        raise Rejected, "larger than #{ImageType::MAX_BYTES} bytes" if response["content-length"].to_i > ImageType::MAX_BYTES

        body = +"".b
        response.read_body do |chunk|
          body << chunk
          raise Rejected, "larger than #{ImageType::MAX_BYTES} bytes" if body.bytesize > ImageType::MAX_BYTES
        end
        body
      end

      def build_request(uri)
        Net::HTTP::Get.new(uri).tap do |request|
          request["User-Agent"] = "shiplog/#{Shiplog::VERSION}"
          request["Authorization"] = "Bearer #{@token}" if @token.present? && uri.host.to_s.downcase == Sources::ATTACHMENTS_HOST
        end
      end

      # A URL for the log without its query string (signed URLs carry a credential there).
      def safe(url) = url.to_s.sub(/[?#].*\z/m, "").first(200)
    end
  end
end
