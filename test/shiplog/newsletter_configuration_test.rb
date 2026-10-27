require "test_helper"

class Shiplog::NewsletterConfigurationTest < ActiveSupport::TestCase
  setup { @config = Shiplog::Configuration.new }

  test "the newsletter is off by default, with its defaults" do
    assert_equal false, @config.newsletter
    assert_nil @config.newsletter_recipients
    assert_nil @config.newsletter_unsubscribe_url
    assert_nil @config.on_newsletter_unsubscribe
    assert_nil @config.newsletter_from
    assert_nil @config.newsletter_address
    assert_nil @config.newsletter_logo_url
    assert_nil @config.newsletter_accent
    assert_equal({}, @config.newsletter_mailer_options)
    assert_equal 500, @config.newsletter_batch_size
  end

  test "newsletter takes true or false only" do
    @config.newsletter = true
    assert @config.newsletter
    assert_raises(ArgumentError) { @config.newsletter = "yes" }
    assert_raises(ArgumentError) { @config.newsletter = nil }
  end

  test "Shiplog.newsletter? needs announcements too" do
    assert_not Shiplog.newsletter?
    Shiplog.config.newsletter = true
    assert Shiplog.newsletter?
    Shiplog.config.announcements = false
    assert_not Shiplog.newsletter?
  end

  test "the callables take nil or something callable" do
    %i[newsletter_recipients newsletter_unsubscribe_url on_newsletter_unsubscribe].each do |setting|
      @config.public_send("#{setting}=", -> { [] })
      assert_respond_to @config.public_send(setting), :call, setting
      @config.public_send("#{setting}=", nil)
      assert_nil @config.public_send(setting)
      error = assert_raises(ArgumentError) { @config.public_send("#{setting}=", "User.all") }
      assert_includes error.message, setting.to_s
    end
  end

  test "the string settings take nil, a blank or a String, stripped" do
    @config.newsletter_from = "  Acme <updates@example.com> "
    assert_equal "Acme <updates@example.com>", @config.newsletter_from
    @config.newsletter_from = ""
    assert_nil @config.newsletter_from
    @config.newsletter_address = "Acme, 1 Main St"
    assert_equal "Acme, 1 Main St", @config.newsletter_address
    assert_raises(ArgumentError) { @config.newsletter_from = 42 }
    assert_raises(ArgumentError) { @config.newsletter_address = [ "a" ] }
  end

  test "newsletter_logo_url must be an http(s) URL" do
    @config.newsletter_logo_url = "https://example.com/logo.png"
    assert_equal "https://example.com/logo.png", @config.newsletter_logo_url
    @config.newsletter_logo_url = nil
    assert_nil @config.newsletter_logo_url
    assert_raises(ArgumentError) { @config.newsletter_logo_url = "/logo.png" }
    assert_raises(ArgumentError) { @config.newsletter_logo_url = "javascript:alert(1)" }
    assert_raises(ArgumentError) { @config.newsletter_logo_url = "https://example.com/a b.png" }
  end

  test "newsletter_accent must be a hex colour, stored lowercased" do
    @config.newsletter_accent = "#0969DA"
    assert_equal "#0969da", @config.newsletter_accent
    @config.newsletter_accent = "#fff"
    assert_equal "#fff", @config.newsletter_accent
    @config.newsletter_accent = nil
    assert_nil @config.newsletter_accent
    assert_raises(ArgumentError) { @config.newsletter_accent = "red" }
    assert_raises(ArgumentError) { @config.newsletter_accent = "#12345" }
    assert_raises(ArgumentError) { @config.newsletter_accent = "#000;background:url(x)" }
  end

  test "newsletter_mailer_options is a Hash with symbol keys, frozen, that cannot touch the recipients or the content" do
    @config.newsletter_mailer_options = { "message_stream" => "broadcast", delivery_method_options: { api_token: "x" } }
    assert_equal({ message_stream: "broadcast", delivery_method_options: { api_token: "x" } }, @config.newsletter_mailer_options)
    assert_predicate @config.newsletter_mailer_options, :frozen?
    @config.newsletter_mailer_options = nil
    assert_equal({}, @config.newsletter_mailer_options)
    assert_raises(ArgumentError) { @config.newsletter_mailer_options = "broadcast" }
    %w[to cc bcc from reply_to subject body template_name].each do |key|
      error = assert_raises(ArgumentError, key) { @config.newsletter_mailer_options = { key => "x" } }
      assert_includes error.message, key
    end
    assert_equal({}, @config.newsletter_mailer_options)
  end

  test "newsletter_batch_size is an Integer between 1 and 10,000" do
    @config.newsletter_batch_size = 100
    assert_equal 100, @config.newsletter_batch_size
    assert_raises(ArgumentError) { @config.newsletter_batch_size = 0 }
    assert_raises(ArgumentError) { @config.newsletter_batch_size = 10_001 }
    assert_raises(ArgumentError) { @config.newsletter_batch_size = "500" }
  end

  test "newsletter is part of the render digest: the form changes the public pages" do
    before = @config.render_digest
    @config.newsletter = true
    assert_not_equal before, @config.render_digest
  end

  test "the boot log says what is missing while the newsletter is on" do
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    Shiplog.log_newsletter_status
    assert_empty log.string

    Shiplog.config.newsletter = true
    Shiplog.log_newsletter_status
    assert_match(/cannot be sent until these are set: newsletter_from, newsletter_address/, log.string)
    assert_match(/Rails.cache is a null store, so the newsletter's subscribe form is not rate limited/, log.string)
    assert_no_match(/on_newsletter_unsubscribe/, log.string)

    log.rewind && log.truncate(0)
    Shiplog.config.newsletter_recipients = -> { [] }
    Shiplog.log_newsletter_status
    assert_match(/newsletter_recipients is set but config.on_newsletter_unsubscribe is not/, log.string)

    log.rewind && log.truncate(0)
    Shiplog.config.on_newsletter_unsubscribe = ->(_email) { nil }
    Shiplog.log_newsletter_status
    assert_no_match(/on_newsletter_unsubscribe/, log.string)
  ensure
    Rails.logger = original
  end
end
