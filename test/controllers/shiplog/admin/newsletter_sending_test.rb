require "test_helper"

# The newsletter on an announcement's admin page: progress, Send test, Send (with its confirmation step), Retry.
class Shiplog::Admin::NewsletterSendingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  ADMIN = "/admin/shiplog".freeze

  setup do
    enable_newsletter!
    Shiplog.config.current_admin = ->(_controller) { "boss@example.com" }
    @entry = approved_announcement
    Shiplog::NewsletterSubscriber.create!(email: "ana@example.com", locale: "en", confirmed_at: Time.current)
  end

  def edit_path(entry = @entry) = "#{ADMIN}/entries/#{entry.id}/edit"

  def newsletter_path(entry = @entry) = "#{ADMIN}/entries/#{entry.id}/newsletter"

  test "the edit page shows the newsletter section with Send test, Send and no progress yet" do
    get edit_path

    assert_response :ok
    assert_select "h3", text: "Newsletter"
    assert_select ".shiplog-admin-newsletter__progress", text: /Not sent yet/
    assert_select "form[action=?]", "#{newsletter_path}/test" do
      assert_select "select[name=test_locale] option[value=en]"
      assert_select "input[type=submit][value=?]", "Send a test to boss@example.com"
    end
    assert_select "a.shiplog-button[href=?]", newsletter_path, text: "Send…"
    assert_select "button[disabled]", text: "Send…", count: 0
    assert_select "a.shiplog-admin-nav__link[href=?]", "#{ADMIN}/newsletter", text: "Newsletter"
  end

  test "the section is absent while the newsletter is off, as is the nav link, and the routes answer 404" do
    Shiplog.config.newsletter = false

    get edit_path
    assert_select "h3", text: "Newsletter", count: 0
    assert_select "a.shiplog-admin-nav__link", text: "Newsletter", count: 0
    get newsletter_path
    assert_response :not_found
    post newsletter_path
    assert_response :not_found
    post "#{newsletter_path}/test", params: { test_locale: "en" }
    assert_response :not_found
    post "#{newsletter_path}/retry"
    assert_response :not_found
  end

  test "Send is disabled with the reasons: not approved, a missing translation, no sender, no address" do
    Shiplog::Entry.find(@entry.id).update!(status: "draft", approved_at: nil)
    Shiplog.config.locales = [ :es ]
    Shiplog.config.newsletter_from = nil
    Shiplog.config.newsletter_address = nil

    get edit_path

    assert_select "button[disabled]", text: "Send…"
    assert_select "a[href=?]", newsletter_path, count: 0
    assert_select "span.shiplog-admin__muted", text: /not approved.*missing or stale \(es\).*newsletter_address.*newsletter_from/
    assert_select "input[type=submit][value=?]", "Send a test to boss@example.com"
  end

  test "Send test needs an admin email" do
    Shiplog.config.current_admin = ->(_controller) { nil }

    get edit_path
    assert_select "input[type=submit][disabled][value=?]", "Send a test to ?"
    assert_select "span", text: /config.current_admin gives no email address/

    assert_no_enqueued_emails do
      post "#{newsletter_path}/test", params: { test_locale: "en" }
    end
    assert_redirected_to edit_path
    follow_redirect!
    assert_select ".shiplog-admin__flash--alert", text: /no email address/
  end

  test "Send test emails the admin in the chosen locale, before approval, without a delivery row" do
    Shiplog.config.locales = [ :es ]
    @entry.translations.create!(locale: "es", title: "Resumen", body: "Texto", source_digest: @entry.translation_source_digest)
    Shiplog::Entry.find(@entry.id).update!(status: "draft", approved_at: nil)

    assert_enqueued_emails 1 do
      post "#{newsletter_path}/test", params: { test_locale: "es", status: "draft" }
    end

    assert_redirected_to "#{edit_path}?status=draft"
    follow_redirect!
    assert_select ".shiplog-admin__flash--notice", text: "Test sent to boss@example.com (es)."
    assert_equal 0, Shiplog::NewsletterDelivery.count
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "boss@example.com" ], mail.to
    assert_equal "Resumen", mail.subject
    assert_equal "boss@example.com", Shiplog::Newsletter::Tokens.email_for(mail["List-Unsubscribe"].to_s[%r{unsubscribe/([A-Za-z0-9_-]+)>}, 1])
  end

  test "Send test is refused without a sender" do
    Shiplog.config.newsletter_from = nil

    assert_no_enqueued_emails do
      post "#{newsletter_path}/test", params: { test_locale: "en" }
    end
    follow_redirect!
    assert_select ".shiplog-admin__flash--alert", text: /newsletter_from/
  end

  test "the confirmation step lists the recipients per locale and what was sent already" do
    Shiplog.config.locales = [ :es ]
    @entry.translations.create!(locale: "es", title: "Resumen", body: "Texto", source_digest: @entry.translation_source_digest)
    Shiplog.config.newsletter_recipients = -> { [ HostUser.new(1, "u1@example.com", "es"), HostUser.new(2, "ana@example.com", "es") ] }

    get newsletter_path

    assert_response :ok
    assert_select "h1", text: "Send the newsletter: October 2026"
    assert_select "table.shiplog-admin-counts" do
      assert_select "tr", text: /es\s*2/
      assert_select "tr", text: /Total\s*2/
    end
    assert_select "form[action=?][method=post] button", newsletter_path, text: "Send to 2 recipients"
    assert_select "button[disabled]", count: 0
    assert_select "a[href=?]", edit_path, text: "Back to the announcement"
  end

  test "the confirmation step keeps the Send button disabled while blocked or without recipients" do
    Shiplog.config.newsletter_address = nil
    get newsletter_path
    assert_select ".shiplog-admin__flash--alert", text: /newsletter_address/
    assert_select "button[disabled]", text: "Send to 1 recipient"

    Shiplog.config.newsletter_address = "Acme"
    Shiplog::NewsletterSubscriber.delete_all
    get newsletter_path
    assert_select "button[disabled]", text: "Send to 0 recipients"
    assert_select "p", text: "Nobody to send to yet."
  end

  test "a recipients callable that raises is shown, never a crash" do
    Shiplog.config.newsletter_recipients = -> { raise "no database" }

    get newsletter_path

    assert_response :ok
    assert_select "[role=alert]", text: /The recipients could not be listed \(RuntimeError\)/
  end

  test "Send enqueues the job and shows the notice" do
    assert_enqueued_with(job: Shiplog::SendNewsletterJob, args: [ @entry ]) do
      post newsletter_path, params: { status: "approved" }
    end

    assert_redirected_to "#{edit_path}?status=approved"
    follow_redirect!
    assert_select ".shiplog-admin__flash--notice", text: /being sent/
  end

  test "Send is refused while blocked" do
    Shiplog.config.locales = [ :es ]

    assert_no_enqueued_jobs only: Shiplog::SendNewsletterJob do
      post newsletter_path
    end
    assert_redirected_to edit_path
    follow_redirect!
    assert_select ".shiplog-admin__flash--alert", text: /missing or stale \(es\)/
  end

  test "the edit page shows the progress, and Retry failed when a delivery failed or stalled" do
    Shiplog::NewsletterDelivery.create!(announcement: @entry, recipient_key: "User/1", locale: "en", status: "sent", sent_at: Time.current)
    Shiplog::NewsletterDelivery.create!(announcement: @entry, recipient_key: "User/2", locale: "en", status: "failed", error: "IOError: down")
    get edit_path
    assert_select ".shiplog-admin-newsletter__progress", text: /1 sent, 1 failed, 0 pending/
    assert_select "form[action=?] button", "#{newsletter_path}/retry", text: "Retry failed"

    Shiplog::NewsletterDelivery.where(recipient_key: "User/2").update_all(status: "sent")
    get edit_path
    assert_select "button", text: "Retry failed", count: 0

    Shiplog::NewsletterDelivery.create!(announcement: @entry, recipient_key: "User/3", locale: "en", status: "pending").update_columns(updated_at: 2.hours.ago)
    get edit_path
    assert_select ".shiplog-admin-newsletter__progress", text: /1 has been pending for more than an hour/
    assert_select "button", text: "Retry failed"
  end

  test "Retry failed enqueues the job with retry_failed" do
    assert_enqueued_with(job: Shiplog::SendNewsletterJob, args: [ @entry, { retry_failed: true } ]) do
      post "#{newsletter_path}/retry"
    end
    assert_redirected_to edit_path
  end

  test "the newsletter routes are not found for a feature" do
    feature = shiplog_entries(:dark_mode_feature)
    get newsletter_path(feature)
    assert_response :not_found
    post newsletter_path(feature)
    assert_response :not_found
    post "#{newsletter_path(feature)}/test"
    assert_response :not_found
  end

  test "sending needs an authorised admin" do
    Shiplog.config.authorize_admin = ->(_controller) { false }

    assert_no_enqueued_jobs only: Shiplog::SendNewsletterJob do
      post newsletter_path
    end
    assert_response :forbidden
  end
end
