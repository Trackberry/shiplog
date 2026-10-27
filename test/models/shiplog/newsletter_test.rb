require "test_helper"

# Shiplog::Newsletter and its helpers: blockers, tokens, the merged recipients, the rendered content, the CSV.
class Shiplog::NewsletterTest < ActiveSupport::TestCase
  setup do
    enable_newsletter!
    @entry = approved_announcement
  end

  def confirmed(email, locale: "en")
    Shiplog::NewsletterSubscriber.create!(email:, locale:, confirmed_at: Time.current)
  end

  def pending(email, locale: "en")
    Shiplog::NewsletterSubscriber.create!(email:, locale:, confirmation_nonce: Shiplog::NewsletterSubscriber.generate_nonce)
  end

  # The decoded ciphertext of a token: "ciphertext--iv--tag", the iv (12 bytes) and the tag (16 bytes) encoded without
  # padding at fixed lengths. Not split on "--", which a URL-safe ciphertext can contain by chance.
  def ciphertext(token) = Base64.urlsafe_decode64(token[0...(token.length - (2 + 16) - (2 + 22))])

  test "blockers are empty for an approved, translated announcement with a sender, an address and an origin" do
    assert_empty Shiplog::Newsletter.blockers(@entry)
    assert Shiplog::Newsletter.sendable?(@entry)
  end

  test "blockers name what is missing" do
    draft = Shiplog::Entry.find(@entry.id).tap { |entry| entry.update!(status: "draft", approved_at: nil) }
    assert_equal [ :not_approved ], Shiplog::Newsletter.blockers(draft)

    Shiplog.config.locales = [ :es ]
    assert_equal [ :not_approved, :translations ], Shiplog::Newsletter.blockers(draft)
    assert_equal [ :es ], Shiplog::Newsletter.missing_locales(draft)
    draft.translations.create!(locale: "es", title: "Resumen", body: "Texto", source_digest: draft.translation_source_digest)
    assert_equal [ :not_approved ], Shiplog::Newsletter.blockers(draft)

    Shiplog.config.newsletter_from = nil
    Shiplog.config.newsletter_address = nil
    assert_equal [ :not_approved, :address, :from ], Shiplog::Newsletter.blockers(draft)
    assert_equal [ :from ], Shiplog::Newsletter.blockers(draft, test: true)
  end

  test "a stale translation blocks the send" do
    Shiplog.config.locales = [ :es ]
    @entry.translations.create!(locale: "es", title: "Resumen", body: "Texto", source_digest: @entry.translation_source_digest)
    assert_empty Shiplog::Newsletter.blockers(@entry)

    @entry.update_columns(body: "Edited")
    assert_equal [ :translations ], Shiplog::Newsletter.blockers(Shiplog::Entry.find(@entry.id))
  end

  test "the origin of links is canonical_url, else the mailer's default host, else nothing" do
    assert_equal "https://example.com", Shiplog::Newsletter.base_url

    Shiplog.config.canonical_url = nil
    assert_equal "https://example.com", Shiplog::Newsletter.base_url # action_mailer.default_url_options in test.rb

    original = ActionMailer::Base.default_url_options
    ActionMailer::Base.default_url_options = { host: "mail.example.com", protocol: "http", port: 3000 }
    assert_equal "http://mail.example.com:3000", Shiplog::Newsletter.base_url
    ActionMailer::Base.default_url_options = {}
    assert_nil Shiplog::Newsletter.base_url
    assert_includes Shiplog::Newsletter.blockers(@entry), :base_url
  ensure
    ActionMailer::Base.default_url_options = original
  end

  test "the sender falls back to ActionMailer's default From" do
    Shiplog.config.newsletter_from = nil
    assert_nil Shiplog::Newsletter.from
    ActionMailer::Base.default from: "noreply@example.com"
    assert_equal "noreply@example.com", Shiplog::Newsletter.from
  ensure
    ActionMailer::Base.default from: nil
  end

  test "the links are absolute and live under /shiplog/newsletter" do
    subscriber = pending("ana@example.com")

    assert_match %r{\Ahttps://example\.com/shiplog/newsletter/unsubscribe/[A-Za-z0-9_-]+\z}, Shiplog::Newsletter.unsubscribe_url("ana@example.com")
    assert_equal "https://example.com/shiplog/newsletter/preferences/#{subscriber.token}", Shiplog::Newsletter.preferences_url(subscriber)
    assert_match %r{\Ahttps://example\.com/shiplog/newsletter/confirm/[A-Za-z0-9_-]+\z}, Shiplog::Newsletter.confirmation_url(subscriber)
    assert_nil Shiplog::Newsletter.confirmation_url(confirmed("b@example.com")), "nothing pending"
    assert_equal "https://example.com/changelog", Shiplog::Newsletter.changelog_url
    assert_equal "https://example.com/changelog/2026-10", Shiplog::Newsletter.announcement_url(@entry, :es)
  end

  test "with external announcements the view link is config.announcement_url, absolute and safe only" do
    Shiplog.config.announcements = :external
    assert_nil Shiplog::Newsletter.announcement_url(@entry, :en)

    calls = []
    Shiplog.config.announcement_url = ->(entry, locale) { calls << [ entry, locale ]; "https://blog.example.com/#{entry.slug}?lang=#{locale}" }
    assert_equal "https://blog.example.com/2026-10?lang=es", Shiplog::Newsletter.announcement_url(@entry, "es")
    assert_equal [ [ @entry, :es ] ], calls

    Shiplog.config.announcement_url = ->(_entry, _locale) { "/relative" }
    assert_nil Shiplog::Newsletter.announcement_url(@entry, :en)
    Shiplog.config.announcement_url = ->(_entry, _locale) { "javascript:alert(1)" }
    assert_nil Shiplog::Newsletter.announcement_url(@entry, :en)
    Shiplog.config.announcement_url = ->(_entry, _locale) { raise "boom" }
    assert_nil Shiplog::Newsletter.announcement_url(@entry, :en)
  end

  test "unsubscribe marks the subscriber row, keeps a suppression row for an unknown address, and tells the host" do
    subscriber = confirmed("Ana@example.com")
    calls = []
    Shiplog.config.on_newsletter_unsubscribe = ->(email) { calls << email }

    assert Shiplog::Newsletter.unsubscribe(" ANA@example.com ")
    assert subscriber.reload.unsubscribed?
    assert_equal [ "ana@example.com" ], calls

    assert Shiplog::Newsletter.unsubscribe("Nobody@example.com"), "a host user without a row"
    assert_equal [ "ana@example.com", "nobody@example.com" ], calls
    row = Shiplog::NewsletterSubscriber.find_by_email("nobody@example.com")
    assert row.unsubscribed?
    assert row.never_confirmed?
    assert_equal 2, Shiplog::NewsletterSubscriber.count
    assert_not Shiplog::Newsletter.unsubscribe("  ")
    assert_not Shiplog::Newsletter.unsubscribe("not an email")
  end

  test "a failing unsubscribe hook is logged without the address, and the row is still marked" do
    subscriber = confirmed("ana@example.com")
    Shiplog.config.on_newsletter_unsubscribe = ->(_email) { raise "CRM down" }
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    assert Shiplog::Newsletter.unsubscribe("ana@example.com")
    assert subscriber.reload.unsubscribed?
    assert_match(/on_newsletter_unsubscribe failed for email:\h{12}: RuntimeError: CRM down/, log.string)
    assert_not_includes log.string, "ana@example.com"
  ensure
    Rails.logger = original
  end

  test "resubscribe lifts the suppression: a suppression-only row is deleted, a former subscriber is confirmed again" do
    Shiplog::Newsletter.unsubscribe("user@example.com")
    assert Shiplog::Newsletter.resubscribe("USER@example.com")
    assert_nil Shiplog::NewsletterSubscriber.find_by_email("user@example.com")

    subscriber = confirmed("ana@example.com")
    Shiplog::Newsletter.unsubscribe("ana@example.com")
    assert Shiplog::Newsletter.resubscribe("ana@example.com")
    assert subscriber.reload.confirmed?

    assert_not Shiplog::Newsletter.resubscribe("ana@example.com"), "not suppressed"
    assert_not Shiplog::Newsletter.resubscribe("unknown@example.com")
  end

  test "the host's unsubscribe URL is used when it is absolute and safe, else nothing, with a log line" do
    user = HostUser.new(1, "u@example.com", "en")
    assert_nil Shiplog::Newsletter.host_unsubscribe_url(user)

    Shiplog.config.newsletter_unsubscribe_url = ->(recipient) { "https://app.example.com/settings/#{recipient.id}" }
    assert_equal "https://app.example.com/settings/1", Shiplog::Newsletter.host_unsubscribe_url(user)
    Shiplog.config.newsletter_unsubscribe_url = ->(_recipient) { "/settings" }
    assert_nil Shiplog::Newsletter.host_unsubscribe_url(user)
    Shiplog.config.newsletter_unsubscribe_url = ->(_recipient) { raise "no route" }
    assert_nil Shiplog::Newsletter.host_unsubscribe_url(user)
  end

  test "locale_for and i18n_locale" do
    assert_equal "en", Shiplog::Newsletter.locale_for(:es)
    Shiplog.config.locales = [ :es, :xx ]
    assert_equal "es", Shiplog::Newsletter.locale_for("es")
    assert_equal "xx", Shiplog::Newsletter.locale_for("xx")
    assert_equal "en", Shiplog::Newsletter.locale_for(nil)
    assert_equal :es, Shiplog::Newsletter.i18n_locale("es")
    assert_equal :en, Shiplog::Newsletter.i18n_locale("xx"), "a configured locale I18n does not know"
    assert_equal :en, Shiplog::Newsletter.i18n_locale(nil)
  end

  test "the rate limit key digests the normalised address" do
    key = Shiplog::Newsletter.rate_limit_key("Ana@Example.com")
    assert_match(/\A\h{64}\z/, key)
    assert_equal key, Shiplog::Newsletter.rate_limit_key(" ana+news@example.com ")
    assert_not_equal key, Shiplog::Newsletter.rate_limit_key("a.na@example.com"), "dots count outside Gmail"
    gmail = Shiplog::Newsletter.rate_limit_key("a.n.a@gmail.com")
    assert_equal gmail, Shiplog::Newsletter.rate_limit_key("ana+x@googlemail.com")
    assert_equal gmail, Shiplog::Newsletter.rate_limit_key("ANA@GMAIL.COM")
  end

  # --- Tokens ---

  test "confirmation tokens find their subscriber for 7 days, then expire; tampering, use and unsubscribing void them" do
    subscriber = pending("ana@example.com")
    token = Shiplog::Newsletter::Tokens.confirmation(subscriber)

    assert_match(/\A[A-Za-z0-9_-]+\z/, token)
    assert_not_includes token, subscriber.id.to_s + "}", "nothing readable"
    assert_not ciphertext(token).include?("nonce"), "encrypted, not just signed"
    assert_equal subscriber, Shiplog::Newsletter::Tokens.subscriber_for(token)
    travel(7.days + 1.minute) { assert_nil Shiplog::Newsletter::Tokens.subscriber_for(token) }
    assert_nil Shiplog::Newsletter::Tokens.subscriber_for(token.sub(/.\z/) { |char| char == "a" ? "b" : "a" })
    assert_nil Shiplog::Newsletter::Tokens.subscriber_for("")
    assert_nil Shiplog::Newsletter::Tokens.subscriber_for(nil)

    subscriber.confirm!
    assert_nil Shiplog::Newsletter::Tokens.subscriber_for(token), "spent"
    assert_nil Shiplog::Newsletter::Tokens.confirmation(subscriber), "nothing pending"

    other = pending("bob@example.com")
    other_token = Shiplog::Newsletter::Tokens.confirmation(other)
    other.unsubscribe!
    assert_nil Shiplog::Newsletter::Tokens.subscriber_for(other_token), "voided by the unsubscribe"
  end

  test "unsubscribe tokens carry the lowercased email encrypted, never expire, and are not confirmation tokens" do
    token = Shiplog::Newsletter::Tokens.unsubscribe(" Ana@Example.com ")

    assert_equal "ana@example.com", Shiplog::Newsletter::Tokens.email_for(token)
    assert_not ciphertext(token).include?("example.com"), "encrypted"
    travel(5.years) { assert_equal "ana@example.com", Shiplog::Newsletter::Tokens.email_for(token) }
    assert_nil Shiplog::Newsletter::Tokens.subscriber_for(token), "a purpose of its own"
    assert_nil Shiplog::Newsletter::Tokens.email_for(Shiplog::Newsletter::Tokens.confirmation(pending("b@example.com")))
    assert_nil Shiplog::Newsletter::Tokens.email_for("#{token}x")
    assert_nil Shiplog::Newsletter::Tokens.email_for(nil)
  end

  test "tokens made with a previous secret_key_base keep working once it is rotated in" do
    old_secret = "the previous secret key base"
    old_key = ActiveSupport::KeyGenerator.new(old_secret, iterations: 1000, hash_digest_class: ActiveSupport::KeyGenerator.hash_digest_class)
      .generate_key(Shiplog::Newsletter::Tokens::SALT, 32)
    old_token = ActiveSupport::MessageEncryptor.new(old_key, url_safe: true, serializer: JSON).encrypt_and_sign({ "email" => "old@example.com" }, purpose: :unsubscribe)

    assert_nil Shiplog::Newsletter::Tokens.email_for(old_token)
    Shiplog::Newsletter::Tokens.rotate(old_secret)
    assert_equal "old@example.com", Shiplog::Newsletter::Tokens.email_for(old_token)
    assert_equal "new@example.com", Shiplog::Newsletter::Tokens.email_for(Shiplog::Newsletter::Tokens.unsubscribe("new@example.com"))
  ensure
    Shiplog::Newsletter::Tokens.reset_rotation!
  end

  # --- Recipients ---

  test "recipients are the host's users then the confirmed subscribers, deduplicated by email, the host's winning" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.newsletter_recipients = -> { [ HostUser.new(42, "Ana@example.com", "es"), HostUser.new(43, "bob@example.com", nil), HostUser.new(44, "ANA@example.com", "en") ] }
    confirmed("ana@example.com", locale: "en")
    carol = confirmed("carol@example.com", locale: "es")
    Shiplog::NewsletterSubscriber.create!(email: "pending@example.com", locale: "en")
    Shiplog::NewsletterSubscriber.create!(email: "gone@example.com", locale: "en", confirmed_at: Time.current, unsubscribed_at: Time.current)

    recipients = Shiplog::Newsletter::Recipients.new.to_enum(:each).to_a

    assert_equal [ "HostUser/42", "HostUser/43", carol.recipient_key ], recipients.map(&:key)
    assert_equal %w[ana@example.com bob@example.com carol@example.com], recipients.map(&:email)
    assert_equal %w[es en es], recipients.map(&:locale)
    assert recipients.first.host?
    assert recipients.last.subscriber?
    assert_equal carol, recipients.last.record
    assert_equal({ "en" => 1, "es" => 2 }, Shiplog::Newsletter::Recipients.new.counts_by_locale)
  end

  test "a host user whose address unsubscribed is skipped, in one query per batch" do
    Shiplog.config.newsletter_recipients = -> { [ HostUser.new(1, "Gone@example.com", "en"), HostUser.new(2, "here@example.com", "en") ] }
    Shiplog::Newsletter.unsubscribe("gone@example.com")

    recipients = nil
    queries = count_queries(ignore_cache: true) { recipients = Shiplog::Newsletter::Recipients.new.to_enum(:each).to_a }

    assert_equal %w[here@example.com], recipients.map(&:email)
    assert_operator queries, :<=, 3, "one for the suppressions, one or two for the subscribers"
  end

  test "a host relation is read in batches, and batches are yielded per source by batch size" do
    users = (1..5).map { |i| HostUser.new(i, "u#{i}@example.com", "en") }
    relation = HostRelation.new(users)
    Shiplog.config.newsletter_recipients = -> { relation }
    confirmed("s@example.com")

    batches = Shiplog::Newsletter::Recipients.new(batch_size: 2).to_enum(:each_batch).to_a

    assert_equal [ 2, 2, 1, 1 ], batches.map(&:size)
    assert_equal [ 2 ], relation.batch_sizes
  end

  test "host objects without a usable email or id, or not responding to the contract, are skipped with a warning that names no address" do
    Shiplog.config.newsletter_recipients = -> { [ HostUser.new(1, "", "en"), HostUser.new(2, "not an email", "en"), Object.new, HostUser.new(nil, "noid@example.com", "en"), HostUser.new(3, "ok@example.com", "en"), nil ] }
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    recipients = Shiplog::Newsletter::Recipients.new.to_enum(:each).to_a

    assert_equal %w[ok@example.com], recipients.map(&:email)
    assert_match(/newsletter_recipients gave Object, which does not respond to email, locale and id/, log.string)
    assert_match(/newsletter_recipients gave a HostUser without an id: skipped/, log.string)
    assert_not_includes log.string, "noid@example.com"
  ensure
    Rails.logger = original
  end

  test "without a recipients callable, the subscribers alone are the recipients" do
    confirmed("s@example.com")
    assert_equal %w[s@example.com], Shiplog::Newsletter::Recipients.new.to_enum(:each).map(&:email)
    Shiplog.config.newsletter_recipients = -> { nil }
    assert_equal %w[s@example.com], Shiplog::Newsletter::Recipients.new.to_enum(:each).map(&:email)
  end

  # --- Content ---

  test "the content renders the translation of the locale, English otherwise, with inline styles" do
    Shiplog.config.locales = [ :es ]
    @entry.update!(title: "October recap", body: "Intro **bold** with [a link](https://example.com/x).\n\n## Highlights\n\n- one")
    @entry.translations.create!(locale: "es", title: "Resumen de octubre", body: "Intro con [un enlace](https://example.com/x).", source_digest: @entry.translation_source_digest)
    Shiplog.config.newsletter_accent = "#ff0000"

    english = Shiplog::Newsletter::Content.new(@entry, "en")
    assert_equal "October recap", english.title
    assert_equal "October 2026", english.month
    assert_includes english.html, %(<h2 style="margin:28px 0 10px;)
    assert_includes english.html, %(<a href="https://example.com/x" style="color:#ff0000;text-decoration:underline;">a link</a>)
    assert_includes english.html, "<strong>bold</strong>"
    assert_includes english.text, "Intro bold with a link (https://example.com/x)."
    assert_equal "Intro bold with a link (https://example.com/x).", english.preheader
    assert_equal "https://example.com/changelog/2026-10", english.view_url

    spanish = Shiplog::Newsletter::Content.new(@entry, :es)
    assert_equal "Resumen de octubre", spanish.title
    assert_equal "octubre 2026", spanish.month
    assert_includes spanish.html, "un enlace"
    assert_equal "en", Shiplog::Newsletter::Content.new(@entry, :fr).locale
  end

  test "the month name falls back to English for a locale without month names" do
    with_extra_locale(:xx) do
      assert_equal "October 2026", Shiplog::Period.month_name(Date.new(2026, 10, 1), locale: :xx)
    end
    assert_equal "October 2026", Shiplog::Period.month_name(Date.new(2026, 10, 1), locale: :nope)
  end

  test "Markdown.to_html with styles escapes the style values and leaves tags without one bare" do
    html = Shiplog::Markdown.to_html("Hi `code` ![alt](https://example.com/i.png)\n\n> quote\n\n---", styles: { "p" => %(a:"b"), "code" => "c:d" })

    assert_includes html, %(<p style="a:&quot;b&quot;">)
    assert_includes html, %(<code style="c:d">code</code>)
    assert_includes html, %(<img src="https://example.com/i.png" alt="alt" loading="lazy">)
    assert_includes html, "<blockquote>"
    assert_includes html, "<hr>"
    assert_equal Shiplog::Markdown.to_html("# T\n\n- a"), Shiplog::Markdown.to_html("# T\n\n- a", styles: {})
  end

  # --- CSV ---

  test "the CSV quotes every cell and neutralises formulas" do
    Shiplog::NewsletterSubscriber.create!(email: "=1+1@example.com", locale: "en", source: "/@cmd|' /C calc'!A0", confirmed_at: Time.zone.local(2026, 10, 2, 9))
    Shiplog::NewsletterSubscriber.create!(email: "plain@example.com", locale: "es", source: %(/changelog?q="quoted"))

    csv = Shiplog::Newsletter::Csv.generate(Shiplog::NewsletterSubscriber.order(:email))
    lines = csv.lines(chomp: true)

    assert_equal %("email","locale","status","source","subscribed_at","confirmed_at","unsubscribed_at"), lines[0]
    assert lines[1].start_with?(%("'=1+1@example.com","en","confirmed","/@cmd|' /C calc'!A0",))
    assert_includes lines[1], %("2026-10-02T09:00:00Z")
    assert lines[2].start_with?(%("plain@example.com","es","pending","/changelog?q=""quoted""",))
    assert lines[2].end_with?(%(,"",""))
    [ "=", "+", "-", "@", "\t", "\r" ].each { |prefix| assert_equal %("'#{prefix}x"), Shiplog::Newsletter::Csv.cell("#{prefix}x"), prefix.inspect }
  end
end
