require "test_helper"

# The subscribe form and its POST: the same answer for every address, the honeypot, the rate limits, no CSRF.
class Shiplog::NewsletterSubscriptionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PATH = "/shiplog/newsletter/subscription".freeze

  setup do
    enable_newsletter!
    @announcement = approved_announcement
  end

  def subscribe(email, **params)
    post PATH, params: { email:, source: "/changelog" }.merge(params)
  end

  test "the form is on the changelog and on announcement pages while the newsletter is on, without a CSRF token" do
    [ "/changelog", "/changelog/2026-10" ].each do |path|
      get path
      assert_response :ok
      assert_select "section.shiplog-newsletter" do
        assert_select "form[action=?][method=post]", PATH do
          assert_select "input[type=email][name=email][required]"
          assert_select "input[name=source][type=hidden][value=?]", path
          assert_select ".shiplog-newsletter__trap input[name=nl_extra][tabindex='-1'][autocomplete=off]"
          assert_select "input[name=website]", count: 0
          assert_select "input[name=authenticity_token]", count: 0
          assert_select "button[type=submit]", text: "Subscribe"
        end
      end
    end
  end

  test "the form is not rendered while the newsletter is off, and the pages answer 404" do
    Shiplog.config.newsletter = false

    get "/changelog"
    assert_select "section.shiplog-newsletter", count: 0
    get "/changelog/2026-10"
    assert_select "section.shiplog-newsletter", count: 0
    get PATH
    assert_response :not_found
    subscribe("ana@example.com")
    assert_response :not_found
    assert_equal 0, Shiplog::NewsletterSubscriber.count
  end

  test "a host renders the form anywhere with the helper" do
    get "/news"

    assert_response :ok
    assert_select "form.shiplog-newsletter__form[action=?]", PATH
    assert_select "input[name=source][value=?]", "/news"
    assert_select "link[rel=stylesheet][href*='shiplog.css']", 1
  end

  test "subscribing creates a pending subscriber with the page's locale and source, emails the confirmation and redirects" do
    assert_enqueued_emails 1 do
      subscribe("  Ana@Example.com ")
    end

    assert_redirected_to PATH
    subscriber = Shiplog::NewsletterSubscriber.find_by!(email: "ana@example.com")
    assert subscriber.pending?
    assert_equal "en", subscriber.locale
    assert_equal "/changelog", subscriber.source
    follow_redirect!
    assert_response :ok
    assert_select "h2", text: "Check your inbox"
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "the locale is the page's, when it is a configured one" do
    Shiplog.config.locales = [ :es ]
    post "/es#{PATH}", params: { email: "ana@example.com" }

    assert_redirected_to "/es#{PATH}"
    assert_equal "es", Shiplog::NewsletterSubscriber.find_by!(email: "ana@example.com").locale

    Shiplog.config.locales = []
    post "/es#{PATH}", params: { email: "bob@example.com" }
    assert_equal "en", Shiplog::NewsletterSubscriber.find_by!(email: "bob@example.com").locale
  end

  test "the answer is the same for a new, a pending, a confirmed and an unsubscribed address" do
    responses = []
    subscribe("ana@example.com")
    responses << [ response.status, response.location, response.body ]
    subscribe("ana@example.com") # pending
    responses << [ response.status, response.location, response.body ]
    Shiplog::NewsletterSubscriber.find_by!(email: "ana@example.com").confirm!
    assert_no_enqueued_emails do
      subscribe("ana@example.com") # confirmed: no new email
    end
    responses << [ response.status, response.location, response.body ]
    Shiplog::NewsletterSubscriber.find_by!(email: "ana@example.com").unsubscribe!
    subscribe("ana@example.com")
    responses << [ response.status, response.location, response.body ]

    assert_equal 1, responses.uniq.size
    assert_equal 302, responses.first.first
    assert_equal 1, Shiplog::NewsletterSubscriber.count
  end

  test "a filled honeypot gets the same redirect and creates nothing" do
    assert_no_enqueued_emails do
      subscribe("bot@example.com", nl_extra: "https://spam.example")
    end

    assert_redirected_to PATH
    assert_equal 0, Shiplog::NewsletterSubscriber.count
  end

  test "an address that is not an email gets the form back with an error" do
    subscribe("not an email")

    assert_response :unprocessable_content
    assert_select ".shiplog-newsletter__notice--error", text: "Enter a valid email address."
    assert_select "input[name=email][value=?]", "not an email"
    assert_equal 0, Shiplog::NewsletterSubscriber.count
  end

  test "odd parameters are tolerated" do
    subscribe([ "a@example.com" ], source: [ "x" ])
    assert_response :unprocessable_content
    post PATH
    assert_response :unprocessable_content
    assert_equal 0, Shiplog::NewsletterSubscriber.count
  end

  test "the source is kept only as a same-site path, else the referrer's path" do
    post PATH, params: { email: "ana@example.com" }, headers: { "Referer" => "https://example.com/changelog/2026-10?x=1" }
    assert_equal "/changelog/2026-10", Shiplog::NewsletterSubscriber.find_by!(email: "ana@example.com").source

    post PATH, params: { email: "bob@example.com", source: "https://evil.example/phish" }, headers: { "Referer" => "https://example.com/news" }
    assert_equal "/news", Shiplog::NewsletterSubscriber.find_by!(email: "bob@example.com").source

    post PATH, params: { email: "carol@example.com", source: "//evil.example" }
    assert_nil Shiplog::NewsletterSubscriber.find_by!(email: "carol@example.com").source
  end

  test "the POST needs no CSRF token (the pages carrying the form are cached)" do
    ActionController::Base.allow_forgery_protection = true
    subscribe("ana@example.com")

    assert_redirected_to PATH
    assert_equal 1, Shiplog::NewsletterSubscriber.count
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "an address is rate limited after 3 attempts an hour (tags and Gmail dots count as one), an IP after 20" do
    counting_cache do |counts|
      subscribe("a.na@gmail.com")
      subscribe("ana+news@gmail.com")
      subscribe("ANA@googlemail.com")
      assert_response :redirect
      subscribe("ana@gmail.com")
      assert_response :too_many_requests
      assert_select "h2", text: "Too many attempts"
      assert_includes response.headers["Cache-Control"], "no-store"
      assert counts.keys.none? { |key| key.include?("gmail") }, "the cache holds digests, not addresses: #{counts.keys.inspect}"

      16.times { |i| subscribe("other#{i}@example.com") }
      assert_response :redirect, "20 attempts from the IP so far"
      subscribe("one-more@example.com")
      assert_response :too_many_requests
    end
  end

  test "all confirmation emails together are capped per hour" do
    counting_cache do |counts|
      counts["rate-limit:shiplog/newsletter/subscriptions:global:all"] = Shiplog::Newsletter::SubscriptionsController::GLOBAL
      subscribe("ana@example.com")

      assert_response :too_many_requests
      assert_equal 0, Shiplog::NewsletterSubscriber.count
    end
  end

  test "the rate limits are off with a cache that counts nothing" do
    5.times { subscribe("ana@example.com") }

    assert_response :redirect
  end
end
