require "net/http"
require "json"
require "uri"

module Shiplog
  module Github
    class Client
      ENDPOINT = URI("https://api.github.com/graphql")
      RETRYABLE_STATUSES = [ 502, 503, 504 ].freeze
      NETWORK_ERRORS = [
        Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
        OpenSSL::SSL::SSLError, SocketError
      ].freeze
      DEFAULT_RESET_WINDOW = 60

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
      rescue *NETWORK_ERRORS => error
        raise Transient, "#{error.class}: #{error.message}"
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
        raise Transient, "GitHub responded with HTTP #{status}" if status >= 500
        raise Error, "GitHub responded with HTTP #{status}" unless status.between?(200, 299)

        body = JSON.parse(response.body)
        errors = body["errors"].to_a
        raise_rate_limited(response) if errors.any? { |e| e["type"] == "RATE_LIMITED" }
        return body.fetch("data") if errors.empty? || not_found_only?(body, errors)

        raise Error, errors.map { |e| e["message"] }.join("; ")
      rescue JSON::ParserError
        raise Error, "GitHub returned an unparseable response"
      end

      # A missing issue/PR number yields `data.repository.issue: null` plus a NOT_FOUND error.
      def not_found_only?(body, errors)
        body["data"].present? && errors.all? { |e| e["type"] == "NOT_FOUND" }
      end

      def rate_limited?(response, status)
        return false unless [ 403, 429 ].include?(status)

        response["x-ratelimit-remaining"] == "0" || response["retry-after"].present?
      end

      def raise_rate_limited(response)
        reset_at = if response["retry-after"].present?
          Time.current + response["retry-after"].to_i
        elsif response["x-ratelimit-reset"].to_i.positive?
          Time.at(response["x-ratelimit-reset"].to_i).utc
        else
          Time.current + DEFAULT_RESET_WINDOW
        end
        raise RateLimited.new(reset_at)
      end
    end
  end
end
