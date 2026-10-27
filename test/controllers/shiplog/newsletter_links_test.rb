require "test_helper"

# The links in emails: confirmation, preferences and unsubscribe. A GET changes nothing; the buttons POST.
class Shiplog::NewsletterLinksTest < ActionDispatch::IntegrationTest
  setup do
    enable_newsletter!
    @calls = []
    Shiplog.config.on_newsletter_unsubscribe = ->(email) { @calls << email }
    @subscriber = Shiplog::NewsletterSubscriber.create!(email: "ana@example.com", locale: "en", confirmation_nonce: Shiplog::NewsletterSubscriber.generate_nonce)
  end

  # One token per test: each one made carries its own expiry time, so two are never equal.
  def confirm_path(token = (@confirm_token ||= Shiplog::Newsletter::Tokens.confirmation(@subscriber))) = "/shiplog/newsletter/confirm/#{token}"

  def preferences_path(token = @subscriber.token) = "/shiplog/newsletter/preferences/#{token}"

  # One token per address: encryption makes every token different, and a page's button must match its URL.
  def unsubscribe_path(email = "ana@example.com")
    (@unsubscribe_tokens ||= {})[email] ||= Shiplog::Newsletter::Tokens.unsubscribe(email)
    "/shiplog/newsletter/unsubscribe/#{@unsubscribe_tokens[email]}"
  end

  def writes = ->(statements) { statements.grep(/\A\s*(UPDATE|INSERT|DELETE)\b/i) }

  # --- Confirmation ---

  test "the confirmation link opens a page with a button and changes nothing" do
    statements = sql_statements { get confirm_path }

    assert_response :ok
    assert_empty writes.(statements)
    assert_select "form[action=?][method=post] button", confirm_path, text: "Confirm"
    assert_select "p", text: /ana@example.com/
    assert @subscriber.reload.pending?
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "the button confirms the subscription, once: the link is spent" do
    post confirm_path

    assert_response :ok
    assert_select "h2", text: "You're subscribed"
    assert_select "a[href=?]", preferences_path
    assert @subscriber.reload.confirmed?
    assert_nil @subscriber.confirmation_nonce

    post confirm_path
    assert_response :not_found, "a replay"
    get confirm_path
    assert_response :not_found
  end

  test "a confirmation link issued before an unsubscribe no longer resubscribes the address" do
    token = Shiplog::Newsletter::Tokens.confirmation(@subscriber)
    @subscriber.confirm!
    Shiplog::Newsletter.unsubscribe("ana@example.com")

    post confirm_path(token)

    assert_response :not_found
    assert @subscriber.reload.unsubscribed?
  end

  test "an expired, tampered or unknown confirmation token is not found, with no hint" do
    token = Shiplog::Newsletter::Tokens.confirmation(@subscriber)
    travel 8.days do
      get confirm_path(token)
      assert_response :not_found
      assert_select "h2", text: "This link is not valid"
      post confirm_path(token)
      assert_response :not_found
    end
    post confirm_path("#{token}x")
    assert_response :not_found
    post confirm_path(Shiplog::Newsletter::Tokens.unsubscribe("ana@example.com"))
    assert_response :not_found, "an unsubscribe token confirms nothing"
    assert @subscriber.reload.pending?
    get "/shiplog/newsletter/confirm/not%20a%20token"
    assert_response :not_found
  end

  test "the confirmation pages are in the subscriber's language" do
    Shiplog.config.locales = [ :es ]
    @subscriber.update!(locale: "es")

    get confirm_path
    assert_select "h2", text: "Confirma tu suscripción"
    assert_select "html[lang=es]"
    post confirm_path
    assert_select "h2", text: "Suscripción confirmada"
  end

  # --- Preferences ---

  test "the preferences page shows the subscription and offers the language, unsubscribe and delete" do
    Shiplog.config.locales = [ :es ]
    @subscriber.confirm!

    get preferences_path

    assert_response :ok
    assert_select "strong", text: "ana@example.com"
    assert_select "p", text: /Status: Subscribed/
    assert_select "select[name=locale] option", count: 2
    assert_select "select[name=locale] option[selected][value=en]"
    assert_select "form[action=?] input[name=subscribed][value='0']", preferences_path
    assert_select "button", text: "Unsubscribe"
    assert_select "button", text: "Resubscribe", count: 0
    assert_select "form[action=?][method=post] input[name=_method][value=delete]", preferences_path
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "changing the language rotates the token: the next page uses the new one, the old link is dead" do
    Shiplog.config.locales = [ :es ]
    old_token = @subscriber.token
    patch preferences_path, params: { locale: "es" }

    @subscriber.reload
    assert_not_equal old_token, @subscriber.token
    assert_redirected_to preferences_path(@subscriber.token)
    assert_equal "es", @subscriber.locale
    follow_redirect!
    assert_select "p[role=status]", text: "Preferencias guardadas."
    assert_select "select[name=locale] option[selected][value=es]"
    get preferences_path(old_token)
    assert_response :not_found

    patch preferences_path, params: { locale: "fr" }
    assert_equal "en", @subscriber.reload.locale, "an unknown locale becomes the default"
  end

  test "unsubscribing from the preferences page removes the address from both lists, and resubscribing needs no confirmation" do
    @subscriber.confirm!
    patch preferences_path, params: { subscribed: "0" }

    @subscriber.reload
    assert_redirected_to preferences_path(@subscriber.token)
    assert @subscriber.unsubscribed?
    assert_equal [ "ana@example.com" ], @calls
    follow_redirect!
    assert_select "p[role=status]", text: "You're unsubscribed."
    assert_select "button", text: "Resubscribe"
    assert_select "button", text: "Unsubscribe", count: 0

    patch preferences_path, params: { subscribed: "1" }
    assert @subscriber.reload.confirmed?
    follow_redirect!
    assert_select "p[role=status]", text: "You're subscribed again."
  end

  test "deleting my data removes the row" do
    delete preferences_path

    assert_response :ok
    assert_select "h2", text: "Your data was deleted"
    assert_nil Shiplog::NewsletterSubscriber.find_by(id: @subscriber.id)
    get preferences_path
    assert_response :not_found
  end

  test "an unknown preferences token is not found and a GET writes nothing" do
    get preferences_path("nope")
    assert_response :not_found
    statements = sql_statements { get preferences_path }
    assert_empty writes.(statements)
  end

  test "the preferences forms need a CSRF token, unlike the one-click endpoint" do
    ActionController::Base.allow_forgery_protection = true

    patch preferences_path, params: { subscribed: "0" }
    assert_response :unprocessable_content
    assert @subscriber.reload.pending?
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  # --- Unsubscribe ---

  test "the unsubscribe link opens a page with a button and changes nothing" do
    @subscriber.confirm!
    statements = sql_statements { get unsubscribe_path }

    assert_response :ok
    assert_empty writes.(statements)
    assert_select "form[action=?][method=post] button", unsubscribe_path, text: "Unsubscribe"
    assert_select "p", text: /ana@example.com/
    assert @subscriber.reload.confirmed?
    assert_empty @calls
  end

  test "the button unsubscribes the address from both lists" do
    @subscriber.confirm!
    post unsubscribe_path

    assert_response :ok
    assert_select "h2", text: "You're unsubscribed"
    assert @subscriber.reload.unsubscribed?
    assert_equal [ "ana@example.com" ], @calls
  end

  test "a host user without a row gets a suppression row and the hook" do
    post unsubscribe_path("user@example.com")

    assert_response :ok
    assert_equal [ "user@example.com" ], @calls
    row = Shiplog::NewsletterSubscriber.find_by_email("user@example.com")
    assert row.unsubscribed?
    assert row.never_confirmed?
  end

  test "the one-click POST of a mail provider needs no CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    @subscriber.confirm!

    post unsubscribe_path, params: { "List-Unsubscribe" => "One-Click" }

    assert_response :ok
    assert @subscriber.reload.unsubscribed?
    assert_equal [ "ana@example.com" ], @calls
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "a tampered unsubscribe token is not found and calls nobody" do
    post "#{unsubscribe_path}x"
    assert_response :not_found
    post "/shiplog/newsletter/unsubscribe/#{Shiplog::Newsletter::Tokens.confirmation(@subscriber)}"
    assert_response :not_found, "a confirmation token unsubscribes nobody"
    assert_empty @calls
  end

  test "a failing host hook still shows the confirmation" do
    Shiplog.config.on_newsletter_unsubscribe = ->(_email) { raise "CRM down" }
    post unsubscribe_path

    assert_response :ok
    assert @subscriber.reload.unsubscribed?
  end

  test "the unsubscribe pages are in the subscriber's language when there is a row, else the page's" do
    Shiplog.config.locales = [ :es ]
    @subscriber.update!(locale: "es")
    get unsubscribe_path
    assert_select "h2", text: "Darse de baja"

    get unsubscribe_path("user@example.com")
    assert_select "h2", text: "Unsubscribe"
    get "/es#{unsubscribe_path("user@example.com")}"
    assert_select "h2", text: "Darse de baja"
  end

  test "unsubscribing and the preferences keep working while the newsletter is off; subscribing and confirming do not" do
    @subscriber.confirm!
    Shiplog.config.newsletter = false

    get unsubscribe_path
    assert_response :ok
    post unsubscribe_path
    assert_response :ok
    assert @subscriber.reload.unsubscribed?
    assert_equal [ "ana@example.com" ], @calls
    get preferences_path
    assert_response :ok
    delete preferences_path
    assert_response :ok
    assert_nil Shiplog::NewsletterSubscriber.find_by(id: @subscriber.id)

    get confirm_path
    assert_response :not_found
    get "/shiplog/newsletter/subscription"
    assert_response :not_found
  end

  test "unsubscribing keeps working with announcements off too" do
    Shiplog.config.announcements = false

    post unsubscribe_path("user@example.com")

    assert_response :ok
    assert_equal [ "user@example.com" ], @calls
  end
end
