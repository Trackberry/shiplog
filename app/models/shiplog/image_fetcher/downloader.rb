require "net/http"

module Shiplog
  class ImageFetcher
    # Downloads one allowed image URL: five seconds to connect and five to read, 15 seconds in total (checked
    # on a monotonic clock while streaming and between redirect hops), at most three redirects (each hop is
    # checked against the allowlist again), at most 5 MB (raw bytes: the response is requested uncompressed, and
    # counted while streaming, the download stops past it). The body of a redirect is read with the same cap
    # and thrown away. The GitHub token is sent to github.com only, never to another host. Returns a Download,
    # or nil (logged) when anything goes wrong or the bytes aren't a PNG, JPEG, GIF or WebP of at most 10,000
    # pixels a side and 40 megapixels (see ImageType).
    class Downloader
      TIMEOUT = 5
      TOTAL_DEADLINE = 15
      MAX_REDIRECTS = 3
      Download = Data.define(:body, :content_type, :width, :height)
      Rejected = Class.new(StandardError)

      # Seconds on the monotonic clock, which wall-clock changes don't move.
      def self.now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def initialize(token: nil)
        @token = token
      end

      # `budget` is the seconds the caller has left; the deadline is the smaller of that and TOTAL_DEADLINE.
      def call(url, budget: nil)
        deadline = self.class.now + [ TOTAL_DEADLINE, budget ].compact.min
        body = fetch(Sources.parse(url), MAX_REDIRECTS, deadline)
        info = ImageType.analyze(body) # type by magic bytes, size from the header, both limits enforced

        Download.new(body:, content_type: info.content_type, width: info.width, height: info.height)
      rescue StandardError => error
        Rails.logger&.warn("[shiplog] Skipped image #{safe(url)}: #{error.class}: #{error.message}")
        nil
      end

      private

      def fetch(uri, redirects_left, deadline)
        raise Rejected, "host or scheme not allowed" unless uri && Sources.allowed?(uri)

        check_deadline!(deadline)
        body = +"".b
        location = nil
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = http.read_timeout = [ TIMEOUT, deadline - self.class.now ].min
        http.request(build_request(uri)) do |response|
          case response
          when Net::HTTPSuccess then body = read(response, deadline)
          when Net::HTTPRedirection
            location = response["location"].to_s
            read(response, deadline, keep: false)
          else raise Rejected, "HTTP #{response.code}"
          end
        end
        return body unless location

        raise Rejected, "too many redirects" if redirects_left.zero?

        fetch(Sources.parse(URI.join(uri.to_s, location).to_s), redirects_left - 1, deadline)
      end

      # Streams the body under the size cap and the deadline. Without `keep` the bytes are counted and dropped
      # (Net::HTTP would otherwise read what is left of the body into memory, uncapped, when the block returns).
      def read(response, deadline, keep: true)
        raise Rejected, "larger than #{ImageType::MAX_BYTES} bytes" if response["content-length"].to_i > ImageType::MAX_BYTES

        body = +"".b
        size = 0
        response.read_body do |chunk|
          check_deadline!(deadline)
          size += chunk.bytesize
          raise Rejected, "larger than #{ImageType::MAX_BYTES} bytes" if size > ImageType::MAX_BYTES

          body << chunk if keep
        end
        body
      end

      def check_deadline!(deadline)
        raise Rejected, "deadline of #{TOTAL_DEADLINE} seconds exceeded" if self.class.now > deadline
      end

      def build_request(uri)
        Net::HTTP::Get.new(uri).tap do |request|
          request["User-Agent"] = "shiplog/#{Shiplog::VERSION}"
          request["Accept-Encoding"] = "identity" # raw bytes only: the cap can't be overshot by inflation
          request["Authorization"] = "Bearer #{@token}" if @token.present? && uri.host.to_s.downcase == Sources::ATTACHMENTS_HOST
        end
      end

      # A URL for the log without its query string (signed URLs carry a credential there).
      def safe(url) = url.to_s.sub(/[?#].*\z/m, "").first(200)
    end
  end
end
