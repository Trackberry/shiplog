require "test_helper"

class Shiplog::SendNewsletterJobTest < ActiveJob::TestCase
  setup do
    enable_newsletter!
    @entry = approved_announcement
    ActionMailer::Base.deliveries.clear
  end

  def confirmed(email, locale: "en")
    Shiplog::NewsletterSubscriber.create!(email:, locale:, confirmed_at: Time.current)
  end

  def deliveries = Shiplog::NewsletterDelivery.where(announcement: @entry).order(:id)

  def delivery_of(subscriber) = deliveries.find_by!(recipient_key: subscriber.recipient_key)

  def send!(**options) = Shiplog::SendNewsletterJob.perform_now(@entry, **options)

  def recipients_sent = ActionMailer::Base.deliveries.map { |mail| mail.to.first }

  test "sends one email per recipient, in their locale, and records a sent delivery row for each, without the address" do
    Shiplog.config.locales = [ :es ]
    @entry.translations.create!(locale: "es", title: "Resumen", body: "Texto", source_digest: @entry.translation_source_digest)
    Shiplog.config.newsletter_recipients = -> { [ HostUser.new(42, "ana@example.com", "es"), HostUser.new(43, "bob@example.com", "en") ] }
    carol = confirmed("carol@example.com", locale: "es")

    send!

    assert_equal 3, ActionMailer::Base.deliveries.size
    assert_equal %w[ana@example.com bob@example.com carol@example.com], recipients_sent
    assert_equal [ "Resumen", @entry.title, "Resumen" ], ActionMailer::Base.deliveries.map(&:subject)
    assert_equal [ "HostUser/42", "HostUser/43", carol.recipient_key ], deliveries.pluck(:recipient_key)
    assert_equal %w[sent sent sent], deliveries.pluck(:status)
    assert_equal %w[es en es], deliveries.pluck(:locale)
    assert deliveries.all?(&:sent_at)
    assert_not Shiplog::NewsletterDelivery.column_names.include?("email")
    assert_equal({ sent: 3, failed: 0, pending: 0, stalled: 0 }, Shiplog::NewsletterDelivery.progress(@entry))
  end

  test "each email carries the recipient's own unsubscribe link, and a subscriber's preferences link" do
    Shiplog.config.newsletter_recipients = -> { [ HostUser.new(42, "ana@example.com", "en") ] }
    Shiplog.config.newsletter_unsubscribe_url = ->(user) { "https://app.example.com/settings/#{user.id}" }
    carol = confirmed("carol@example.com")

    send!

    ana, carol_mail = ActionMailer::Base.deliveries
    ana_token = ana["List-Unsubscribe"].to_s[%r{unsubscribe/([A-Za-z0-9_-]+)>}, 1]
    assert_equal "ana@example.com", Shiplog::Newsletter::Tokens.email_for(ana_token)
    assert_includes ana.html_part.body.to_s, %(href="https://app.example.com/settings/42")
    carol_token = carol_mail["List-Unsubscribe"].to_s[%r{unsubscribe/([A-Za-z0-9_-]+)>}, 1]
    assert_equal "carol@example.com", Shiplog::Newsletter::Tokens.email_for(carol_token)
    assert_includes carol_mail.html_part.body.to_s, %(href="https://example.com/shiplog/newsletter/preferences/#{carol.token}")
  end

  test "an address that unsubscribed is skipped, also when the host's list still has it" do
    Shiplog.config.newsletter_recipients = -> { [ HostUser.new(42, "Ana@example.com", "en"), HostUser.new(43, "bob@example.com", "en") ] }
    Shiplog::Newsletter.unsubscribe("ana@example.com")

    send!

    assert_equal %w[bob@example.com], recipients_sent
    assert_equal [ "HostUser/43" ], deliveries.pluck(:recipient_key)
  end

  test "running the job again, or twice at once, never sends twice" do
    confirmed("ana@example.com")
    send!
    send!
    perform_enqueued_jobs { Shiplog::SendNewsletterJob.perform_later(@entry) }

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal 1, deliveries.count
  end

  test "a recipient added later is sent on the next run only" do
    confirmed("ana@example.com")
    send!
    confirmed("bob@example.com")
    send!

    assert_equal %w[ana@example.com bob@example.com], recipients_sent
  end

  test "the delivery row is written before the email leaves: a crash after the insert sends nothing again" do
    subscriber = confirmed("ana@example.com")
    Shiplog::NewsletterDelivery.create!(announcement: @entry, recipient_key: subscriber.recipient_key, locale: "en", status: "pending")

    send!

    assert_empty ActionMailer::Base.deliveries
  end

  test "a failed delivery is recorded with a scrubbed error and the run goes on; Retry failed sends it again" do
    bad = confirmed("bad@example.com")
    confirmed("good@example.com")
    original = Shiplog::NewsletterMailer.method(:announcement)
    failing = lambda do |entry, email, **options|
      raise IOError, "smtp down for <bad@example.com>" if email == "bad@example.com"
      original.call(entry, email, **options)
    end

    with_stub(Shiplog::NewsletterMailer, :announcement, failing) { send! }

    assert_equal %w[good@example.com], recipients_sent
    row = delivery_of(bad)
    assert_equal "failed", row.status
    assert_equal "IOError: smtp down for <[email]>", row.error
    assert_equal({ sent: 1, failed: 1, pending: 0, stalled: 0 }, Shiplog::NewsletterDelivery.progress(@entry))

    send!
    assert_equal 1, ActionMailer::Base.deliveries.size, "a plain run leaves failed rows alone"

    send!(retry_failed: true)
    assert_equal %w[good@example.com bad@example.com], recipients_sent
    assert_equal "sent", row.reload.status
    assert_nil row.error
  end

  test "Retry failed also sends the rows left pending for more than an hour, and nothing else" do
    stalled = confirmed("stalled@example.com")
    fresh = confirmed("fresh@example.com")
    confirmed("sent@example.com")
    send!
    ActionMailer::Base.deliveries.clear
    delivery_of(stalled).update_columns(status: "pending", updated_at: 2.hours.ago)
    delivery_of(fresh).update_columns(status: "pending", updated_at: 5.minutes.ago)
    assert_equal 1, Shiplog::NewsletterDelivery.progress(@entry)[:stalled]

    send!(retry_failed: true)

    assert_equal %w[stalled@example.com], recipients_sent
    assert_equal "sent", delivery_of(stalled).status
    assert_equal "pending", delivery_of(fresh).status
  end

  test "reclaiming is one statement: a second retry at the same time gets nothing to send" do
    subscriber = confirmed("ana@example.com")
    send!
    delivery_of(subscriber).update_columns(status: "failed", error: "x")

    assert_equal [ subscriber.recipient_key ], Shiplog::NewsletterDelivery.reclaim(@entry)
    assert_equal [], Shiplog::NewsletterDelivery.reclaim(@entry)
    assert_equal "pending", delivery_of(subscriber).status
  end

  test "a reclaimed row whose recipient is gone ends as failed with the reason, not pending forever" do
    gone = confirmed("gone@example.com")
    confirmed("here@example.com")
    send!
    ActionMailer::Base.deliveries.clear
    delivery_of(gone).update_columns(status: "failed", error: "IOError: down")
    gone.update_columns(unsubscribed_at: Time.current)

    send!(retry_failed: true)

    assert_empty ActionMailer::Base.deliveries
    row = delivery_of(gone)
    assert_equal "failed", row.status
    assert_equal Shiplog::NewsletterDelivery::MISSING_RECIPIENT, row.error
  end

  test "a row is touched right before its email is sent, so it never looks stalled while in flight" do
    subscriber = confirmed("ana@example.com")
    Shiplog::NewsletterDelivery.create!(announcement: @entry, recipient_key: subscriber.recipient_key, locale: "en", status: "pending")
      .update_columns(updated_at: 3.hours.ago)
    delivery = delivery_of(subscriber)

    Shiplog::NewsletterDelivery.mark_sending(@entry, subscriber.recipient_key)

    assert_operator delivery.reload.updated_at, :>, 1.minute.ago
    assert_equal 0, Shiplog::NewsletterDelivery.progress(@entry)[:stalled]
  end

  test "recipients are claimed in chunks of CLAIM_SIZE within batches of config.newsletter_batch_size" do
    Shiplog.config.newsletter_batch_size = 2
    5.times { |i| confirmed("u#{i}@example.com") }

    statements = sql_statements { send! }

    assert_equal 3, statements.grep(/INSERT INTO "shiplog_newsletter_deliveries"/).size
    assert_equal 5, ActionMailer::Base.deliveries.size
  end

  test "the body is rendered once per locale, not once per recipient" do
    Shiplog.config.locales = [ :es ]
    @entry.translations.create!(locale: "es", title: "Resumen", body: "Texto", source_digest: @entry.translation_source_digest)
    3.times { |i| confirmed("en#{i}@example.com") }
    2.times { |i| confirmed("es#{i}@example.com", locale: "es") }
    renders = 0
    original = Shiplog::Markdown.method(:to_html)
    counting = ->(*args, **options) { renders += 1; original.call(*args, **options) }

    with_stub(Shiplog::Markdown, :to_html, counting) { send! }

    assert_equal 2, renders
    assert_equal 5, ActionMailer::Base.deliveries.size
  end

  test "nothing is sent while the newsletter is off or the announcement cannot be sent" do
    confirmed("ana@example.com")

    Shiplog.config.newsletter = false
    send!
    assert_empty ActionMailer::Base.deliveries
    assert_equal 0, deliveries.count

    Shiplog.config.newsletter = true
    Shiplog.config.newsletter_address = nil
    send!
    assert_empty ActionMailer::Base.deliveries

    Shiplog.config.newsletter_address = "Acme, 1 Main St"
    Shiplog.config.locales = [ :es ]
    send!
    assert_empty ActionMailer::Base.deliveries, "a missing translation"

    Shiplog.config.locales = []
    send!
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "the log names recipient keys, never addresses" do
    confirmed("secret@example.com")
    failing = ->(*_args, **_options) { raise IOError, "rejected secret@example.com" }
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    with_stub(Shiplog::NewsletterMailer, :announcement, failing) { send! }

    assert_not_includes log.string, "secret@example.com"
    assert_match(/to Subscriber\/\d+ failed: IOError: rejected \[email\]/, log.string)
  ensure
    Rails.logger = original
  end

  test "a job for a deleted announcement is dropped" do
    Shiplog::SendNewsletterJob.perform_later(@entry)
    @entry.destroy!

    assert_nothing_raised { perform_enqueued_jobs }
    assert_empty ActionMailer::Base.deliveries
  end

  test "deleting an announcement deletes its delivery rows" do
    confirmed("ana@example.com")
    send!
    assert_equal 1, deliveries.count

    @entry.destroy!

    assert_equal 0, Shiplog::NewsletterDelivery.count
  end
end
