require "test_helper"

class Shiplog::WebhookSignatureTest < ActiveSupport::TestCase
  def sign(body, secret = "s3cret") = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, body)

  test "valid for the HMAC of the body" do
    assert Shiplog::WebhookSignature.new(secret: "s3cret", body: "{}", header: sign("{}")).valid?
  end

  test "invalid for another secret, another body, a blank or malformed header" do
    assert_not Shiplog::WebhookSignature.new(secret: "s3cret", body: "{}", header: sign("{}", "other")).valid?
    assert_not Shiplog::WebhookSignature.new(secret: "s3cret", body: "{}", header: sign("[]")).valid?
    assert_not Shiplog::WebhookSignature.new(secret: "s3cret", body: "{}", header: nil).valid?
    assert_not Shiplog::WebhookSignature.new(secret: "s3cret", body: "{}", header: "").valid?
    assert_not Shiplog::WebhookSignature.new(secret: "s3cret", body: "{}", header: "garbage").valid?
  end
end
