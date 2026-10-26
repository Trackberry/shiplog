require "net/http"
require "json"
require "uri"

module Shiplog
  module Github
    class Client
      ENDPOINT = URI("https://api.github.com/graphql")
      RETRYABLE_STATUSES = [ 502, 503, 504 ].freeze

      def initialize(token: Shiplog.config.resolved_github_token, retry_delay: 1)
        @token = token
        @retry_delay = retry_delay
      end

      def query(query, variables = {})
        raise Error, "No GitHub token configured (Shiplog.config.github_token)" if @token.blank?

        response = post(JSON.generate(query:, variables:))
        handle(response)
      end

      private

      def post(payload, retried: false)
        response = request(payload)
        return response unless RETRYABLE_STATUSES.include?(response.code.to_i) && !retried

        sleep @retry_delay
        post(payload, retried: true)
      end

      def request(payload)
        http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 30
        http.request(build_request(payload))
      end

      def build_request(payload)
        Net::HTTP::Post.new(ENDPOINT).tap do |req|
          req["Authorization"] = "Bearer #{@token}"
          req["Content-Type"] = "application/json"
          req["User-Agent"] = "shiplog/#{Shiplog::VERSION}"
          req.body = payload
        end
      end

      def handle(response)
        status = response.code.to_i
        raise_rate_limited(response) if rate_limited?(response, status)
        raise Error, "GitHub responded with HTTP #{status}" unless status.between?(200, 299)

        body = JSON.parse(response.body)
        raise Error, body["errors"].map { |e| e["message"] }.join("; ") if body["errors"].present?

        body.fetch("data")
      rescue JSON::ParserError
        raise Error, "GitHub returned an unparseable response"
      end

      def rate_limited?(response, status)
        return false unless [ 403, 429 ].include?(status)

        response["x-ratelimit-remaining"] == "0" || response["retry-after"].present?
      end

      def raise_rate_limited(response)
        reset_at = if response["retry-after"].present?
          Time.current + response["retry-after"].to_i
        else
          Time.at(response["x-ratelimit-reset"].to_i).utc
        end
        raise RateLimited.new(reset_at)
      end
    end
  end
end
