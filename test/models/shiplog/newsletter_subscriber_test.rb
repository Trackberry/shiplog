require "test_helper"

class Shiplog::NewsletterSubscriberTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup { enable_newsletter! }

  def subscribe(email = "Ana@Example.com", locale: :en, source: "/changelog")
    Shiplog::NewsletterSubscriber.subscribe(email, locale:, source:)
  end

  test "the form creates a pending subscriber, lowercased and stripped, with a confirmation nonce, and emails the confirmation by id" do
    subscriber = nil
    assert_enqueued_emails 1 do
      subscriber = subscribe("  Ana@Example.com ")
    end

    assert subscriber.persisted?
    assert_equal "ana@example.com", subscriber.email
    assert_equal "en", subscriber.locale
    assert_equal "/changelog", subscriber.source
    assert subscriber.pending?
    assert_nil subscriber.confirmed_at
    assert_match(/\A[A-Za-z0-9]{32}\z/, subscriber.token)
    assert_match(/\A[A-Za-z0-9]{32}\z/, subscriber.confirmation_nonce)
    assert_enqueued_email_with Shiplog::NewsletterMailer, :confirmation, args: [ subscriber.id ]
  end

  test "an address that is not an email is refused" do
    assert_no_enqueued_emails do
      assert_nil subscribe("not an email")
      assert_nil subscribe("")
      assert_nil subscribe("ana@")
      assert_nil subscribe("#{"a" * 250}@example.com")
    end
    assert_equal 0, Shiplog::NewsletterSubscriber.count
  end

  test "a pending address subscribing again gets a fresh link and keeps its locale and source" do
    Shiplog.config.locales = [ :es ]
    first = subscribe
    nonce = first.confirmation_nonce
    assert_enqueued_emails 1 do
      again = subscribe("ANA@example.com", locale: :es, source: "/changelog/2026-10")
      assert_equal first, again
    end

    first.reload
    assert_equal "en", first.locale, "an anonymous submission does not rewrite the locale"
    assert_equal "/changelog", first.source
    assert_not_equal nonce, first.confirmation_nonce, "the previous link stops working"
    assert_equal 1, Shiplog::NewsletterSubscriber.count
  end

  test "a confirmed address subscribing again gets no email" do
    subscriber = subscribe
    subscriber.confirm!

    assert_no_enqueued_emails do
      assert_equal subscriber, subscribe
    end
    assert subscriber.reload.confirmed?
    assert_nil subscriber.confirmation_nonce
  end

  test "an unsubscribed address subscribing again must confirm again, and stays suppressed until then" do
    subscriber = subscribe
    subscriber.confirm!
    subscriber.unsubscribe!
    assert subscriber.unsubscribed?

    assert_enqueued_emails 1 do
      subscribe
    end
    subscriber.reload
    assert subscriber.unsubscribed?, "still suppressed"
    assert_nil subscriber.confirmed_at
    assert subscriber.confirmation_nonce
    assert_not_includes Shiplog::NewsletterSubscriber.confirmed, subscriber

    subscriber.confirm!
    assert subscriber.confirmed?
    assert_nil subscriber.unsubscribed_at
  end

  test "a locale that is not configured becomes the default locale" do
    assert_equal "en", subscribe("a@example.com", locale: :es).locale
    Shiplog.config.locales = [ :es ]
    assert_equal "es", subscribe("b@example.com", locale: :es).locale
    assert_equal "en", subscribe("c@example.com", locale: :fr).locale
  end

  test "emails are unique whatever their case" do
    subscribe("ana@example.com")
    assert_raises(ActiveRecord::RecordNotUnique) do
      Shiplog::NewsletterSubscriber.transaction(requires_new: true) do
        Shiplog::NewsletterSubscriber.create!(email: "other@example.com", locale: "en").update_column(:email, "ANA@example.com")
      end
    end
    assert_equal subscribe("ana@example.com"), Shiplog::NewsletterSubscriber.find_by_email(" ANA@EXAMPLE.COM ")
  end

  test "two first submissions of the same address at once: the second finds the first's row" do
    existing = Shiplog::NewsletterSubscriber.create!(email: "ana@example.com", locale: "en")
    calls = 0
    original = Shiplog::NewsletterSubscriber.method(:find_by_email)
    racing = ->(email) { (calls += 1) == 1 ? nil : original.call(email) } # the row appears between the lookup and the insert

    subscriber = with_stub(Shiplog::NewsletterSubscriber, :find_by_email, racing) { subscribe("ana@example.com") }

    assert_equal existing, subscriber
    assert_equal 1, Shiplog::NewsletterSubscriber.count
    assert existing.reload.confirmation_nonce
  end

  test "statuses: pending, confirmed, unsubscribed, and resubscribe" do
    subscriber = subscribe
    assert_equal "pending", subscriber.status
    subscriber.confirm!
    assert_equal "confirmed", subscriber.status
    subscriber.unsubscribe!
    assert_equal "unsubscribed", subscriber.status
    subscriber.resubscribe!
    assert_equal "confirmed", subscriber.status
    assert_includes Shiplog::NewsletterSubscriber.confirmed, subscriber
  end

  test "confirm! and unsubscribe! are idempotent and spend the confirmation nonce" do
    subscriber = subscribe
    assert subscriber.confirmation_nonce
    subscriber.confirm!
    assert_nil subscriber.confirmation_nonce
    first = subscriber.confirmed_at
    travel 1.hour do
      subscriber.confirm!
      assert_equal first, subscriber.confirmed_at
      subscriber.unsubscribe!
      at = subscriber.unsubscribed_at
      subscriber.unsubscribe!
      assert_equal at, subscriber.unsubscribed_at
    end

    pending = subscribe("b@example.com")
    pending.unsubscribe!
    assert_nil pending.confirmation_nonce, "an unsubscribe voids a pending link"
  end

  test "suppress marks an existing row, or creates a suppression record for an address that has none" do
    confirmed = subscribe("ana@example.com").tap(&:confirm!)

    assert_equal confirmed, Shiplog::NewsletterSubscriber.suppress(" ANA@example.com ")
    assert confirmed.reload.unsubscribed?

    row = Shiplog::NewsletterSubscriber.suppress("user@example.com")
    assert row.persisted?
    assert row.unsubscribed?
    assert row.never_confirmed?
    assert_equal "en", row.locale
    assert_nil row.source
    assert_nil Shiplog::NewsletterSubscriber.suppress("not an email")
  end

  test "the source is kept only as a same-site path, cleaned and capped" do
    assert_equal "/changelog/2026-10?x=1", subscribe("a@example.com", source: " /chan\x00gelog/2026-10?x=1 ").source
    assert_nil subscribe("b@example.com", source: "/#{"x" * 300}").source
    assert_nil subscribe("c@example.com", source: "https://evil.example/changelog").source
    assert_nil subscribe("d@example.com", source: "//evil.example").source
    assert_nil subscribe("e@example.com", source: "changelog").source
    assert_nil subscribe("f@example.com", source: "   ").source
    assert_nil subscribe("g@example.com", source: nil).source
  end

  test "purge_pending deletes only pending rows untouched for 30 days, and the job purges old deliveries too" do
    old_pending = subscribe("old@example.com")
    old_confirmed = subscribe("confirmed@example.com").tap(&:confirm!)
    old_unsubscribed = subscribe("gone@example.com").tap(&:confirm!).tap(&:unsubscribe!)
    Shiplog::NewsletterSubscriber.where(id: [ old_pending, old_confirmed, old_unsubscribed ]).update_all(updated_at: 31.days.ago)
    resent = subscribe("resent@example.com")
    Shiplog::NewsletterSubscriber.where(id: resent).update_all(updated_at: 31.days.ago)
    subscribe("resent@example.com") # a new link touches the row
    entry = approved_announcement
    Shiplog::NewsletterDelivery.create!(announcement: entry, recipient_key: "User/1", locale: "en", status: "sent").update_columns(created_at: 181.days.ago)
    Shiplog::NewsletterDelivery.create!(announcement: entry, recipient_key: "User/2", locale: "en", status: "sent")

    assert_equal({ subscribers: 1, deliveries: 1 }, Shiplog::PurgeNewsletterJob.perform_now)
    assert_equal [ old_confirmed, old_unsubscribed, resent ].map(&:id).sort, Shiplog::NewsletterSubscriber.pluck(:id).sort
    assert_equal [ "User/2" ], Shiplog::NewsletterDelivery.pluck(:recipient_key)
    assert_equal({ subscribers: 0, deliveries: 0 }, Shiplog::PurgeNewsletterJob.perform_now)
  end

  test "deleting a subscriber deletes its delivery rows" do
    subscriber = subscribe.tap(&:confirm!)
    entry = approved_announcement
    Shiplog::NewsletterDelivery.create!(announcement: entry, recipient_key: subscriber.recipient_key, locale: "en", status: "sent")
    Shiplog::NewsletterDelivery.create!(announcement: entry, recipient_key: "User/1", locale: "en", status: "sent")

    subscriber.destroy!

    assert_equal [ "User/1" ], Shiplog::NewsletterDelivery.pluck(:recipient_key)
  end

  test "rotate_token! gives a new preferences token" do
    subscriber = subscribe
    token = subscriber.token
    subscriber.rotate_token!

    assert_not_equal token, subscriber.reload.token
    assert_match(/\A[A-Za-z0-9]{32}\z/, subscriber.token)
  end

  test "counts_by_locale gives every status per locale" do
    Shiplog.config.locales = [ :es ]
    subscribe("a@example.com").confirm!
    subscribe("b@example.com", locale: :es).confirm!
    subscribe("c@example.com", locale: :es)
    subscribe("d@example.com", locale: :es).tap(&:confirm!).unsubscribe!

    assert_equal({ "en" => { "pending" => 0, "confirmed" => 1, "unsubscribed" => 0 },
                   "es" => { "pending" => 1, "confirmed" => 1, "unsubscribed" => 1 } }, Shiplog::NewsletterSubscriber.counts_by_locale)
    assert_equal({}, Shiplog::NewsletterSubscriber.none.counts_by_locale)
  end

  test "search matches part of the address, case-insensitively, with LIKE wildcards escaped" do
    subscribe("ana@example.com")
    subscribe("bob@example.org")
    subscribe("a_b@example.net")

    assert_equal %w[ana@example.com], Shiplog::NewsletterSubscriber.search("ANA").pluck(:email)
    assert_equal %w[a_b@example.net], Shiplog::NewsletterSubscriber.search("a_b").pluck(:email)
    assert_equal 3, Shiplog::NewsletterSubscriber.search("  ").count
    assert_equal 0, Shiplog::NewsletterSubscriber.search("%").count
  end

  test "recipient_key names the subscriber" do
    subscriber = subscribe
    assert_equal "Subscriber/#{subscriber.id}", subscriber.recipient_key
  end
end
