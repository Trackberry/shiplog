module Shiplog
  class WebhookSignature
    def initialize(secret:, body:, header:)
      @secret = secret
      @body = body
      @header = header
    end

    def valid?
      return false if @header.blank?

      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", @secret, @body)
      Rack::Utils.secure_compare(expected, @header)
    end
  end
end
