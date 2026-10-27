require "test_helper"

class Shiplog::AnnouncementHookTest < ActiveJob::TestCase
  setup do
    @entry = Shiplog::Announcements.draft(month: Date.new(2026, 10, 1))
    @calls = []
    Shiplog.config.on_announcement_approved = ->(entry) { @calls << entry }
    clear_enqueued_jobs
  end

  def approve! = @entry.approve!(by: "ed@example.com")

  def translate!(title: "Novedades", body: @entry.body)
    @entry.translations.create!(locale: "es", title:, body:, source_digest: @entry.translation_source_digest)
  end

  test "approving an announcement enqueues an AnnounceJob" do
    assert_enqueued_with(job: Shiplog::AnnounceJob, args: [ @entry ]) { approve! }
  end

  test "without locales the hook is called once with the entry and announced_at is set" do
    approve!
    perform_enqueued_jobs

    assert_equal [ @entry ], @calls
    assert @entry.reload.announced_at
  end

  test "the announcement_approved.shiplog notification fires with the announcement" do
    payloads = []
    callback = ->(*, payload) { payloads << payload }

    ActiveSupport::Notifications.subscribed(callback, "announcement_approved.shiplog") do
      approve!
      perform_enqueued_jobs
    end

    assert_equal 1, payloads.size
    assert_equal @entry, payloads.first[:announcement]
  end

  test "the hook also runs when announcements are published externally" do
    Shiplog.config.announcements = :external
    approve!
    perform_enqueued_jobs

    assert_equal [ @entry ], @calls
  end

  test "without a hook the announcement is still marked announced" do
    Shiplog.config.on_announcement_approved = nil
    approve!
    perform_enqueued_jobs

    assert @entry.reload.announced_at
  end

  test "with locales but no rewriter the hook is called at approval" do
    Shiplog.config.locales = [ :es ]
    approve!
    perform_enqueued_jobs only: Shiplog::AnnounceJob

    assert_equal [ @entry ], @calls
    assert @entry.reload.announced_at
  end

  test "force calls the hook even with missing translations, and never twice" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = ->(_prompt) { "{}" }
    approve!
    Shiplog::AnnounceJob.perform_now(@entry)
    assert_empty @calls

    Shiplog::AnnounceJob.perform_now(@entry, force: true)
    Shiplog::AnnounceJob.perform_now(@entry, force: true)
    Shiplog::AnnounceJob.perform_now(@entry)

    assert_equal [ @entry ], @calls
    assert @entry.reload.announced_at
  end

  test "force does not announce a draft" do
    Shiplog::AnnounceJob.perform_now(@entry, force: true)

    assert_empty @calls
  end

  test "announce! runs the block once under the lock and stores announced_at only afterwards" do
    approve!
    seen = nil

    assert @entry.announce! { seen = Shiplog::Entry.where(id: @entry.id).pick(:announced_at) }
    assert_nil seen
    assert_not @entry.announce! { flunk "ran twice" }
    assert @entry.reload.announced_at
  end

  test "translations_ready? is true without a rewriter and needs current translations with one" do
    Shiplog.config.locales = [ :es ]
    assert @entry.translations_ready?

    Shiplog.config.rewriter = ->(_prompt) { "{}" }
    assert_not @entry.translations_ready?

    translate!
    assert @entry.translations_ready?
  end

  test "with locales and a rewriter the hook waits for a current translation" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = ->(_prompt) { "{}" }
    approve!
    perform_enqueued_jobs only: Shiplog::AnnounceJob

    assert_empty @calls
    assert_nil @entry.reload.announced_at

    translate!
    Shiplog::AnnounceJob.perform_now(@entry)

    assert_equal [ @entry ], @calls
    assert @entry.reload.announced_at
  end

  test "a stale translation does not count" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = ->(_prompt) { "{}" }
    approve!
    translate!
    @entry.update_columns(body: "Edited English text")
    Shiplog::AnnounceJob.perform_now(@entry)

    assert_empty @calls
  end

  test "the translation job announces the entry once the last translation is in" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = ->(_prompt) { '{"title":"Novedades","body":"Texto"}' }
    approve!
    clear_enqueued_jobs

    Shiplog::TranslateEntryJob.perform_now(@entry, :es)
    assert_enqueued_with(job: Shiplog::AnnounceJob, args: [ @entry ])
    perform_enqueued_jobs only: Shiplog::AnnounceJob

    assert_equal [ @entry ], @calls
  end

  test "a translation job for a feature does not enqueue an AnnounceJob" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = ->(_prompt) { '{"title":"Modo oscuro","body":"Texto"}' }

    assert_no_enqueued_jobs only: Shiplog::AnnounceJob do
      Shiplog::TranslateEntryJob.perform_now(shiplog_entries(:dark_mode_feature), :es)
    end
  end

  test "running the job twice calls the hook once" do
    approve!
    2.times { Shiplog::AnnounceJob.perform_now(@entry) }

    assert_equal 1, @calls.size
  end

  test "a draft announcement is not announced" do
    Shiplog::AnnounceJob.perform_now(@entry)

    assert_empty @calls
    assert_nil @entry.reload.announced_at
  end

  test "a hook that raises gives the claim back, so a retry announces again" do
    Shiplog.config.on_announcement_approved = ->(_entry) { raise "mail server down" }
    approve!

    Shiplog::AnnounceJob.perform_now(@entry)

    assert_nil @entry.reload.announced_at
    assert_enqueued_with(job: Shiplog::AnnounceJob)

    Shiplog.config.on_announcement_approved = ->(entry) { @calls << entry }
    Shiplog::AnnounceJob.perform_now(@entry)

    assert_equal [ @entry ], @calls
    assert @entry.reload.announced_at
  end

  test "regenerating clears announced_at, and approving again announces again" do
    approve!
    perform_enqueued_jobs
    assert @entry.reload.announced_at

    Shiplog.config.rewriter = ->(_prompt) { '{"title":"Second take","body":"New text"}' }
    Shiplog::Rewriter.new(@entry).call(force: true)

    assert @entry.reload.draft?
    assert_nil @entry.announced_at

    approve!
    perform_enqueued_jobs

    assert_equal 2, @calls.size
    assert @entry.reload.announced_at
  end

  test "moving an announcement back to draft clears announced_at" do
    approve!
    perform_enqueued_jobs
    entry = Shiplog::Entry.find(@entry.id)
    assert entry.announced_at

    entry.update!(status: "draft", approved_at: nil)

    assert_nil entry.reload.announced_at
  end

  test "moving an announcement back to draft clears announced_at even through a stale instance" do
    approve!
    perform_enqueued_jobs

    @entry.update!(status: "draft", approved_at: nil)

    assert_nil @entry.reload.announced_at
  end

  test "discarding and restoring a feature leaves announced_at alone" do
    feature = shiplog_entries(:csv_change_draft)
    feature.update_columns(announced_at: Time.zone.local(2026, 10, 1))

    feature.discard!(reason: "no")
    feature.restore!

    assert_equal Time.zone.local(2026, 10, 1), feature.reload.announced_at
  end

  test "unseen_announcements_count is 0 when announcements are off" do
    approve!
    Shiplog.config.announcements = false

    assert_equal 0, Shiplog.unseen_announcements_count
  end

  test "with announcements off the hook is never called" do
    approve!
    Shiplog.config.announcements = false
    perform_enqueued_jobs

    assert_empty @calls
    assert_nil @entry.reload.announced_at
  end

  test "approving a feature never enqueues an AnnounceJob" do
    assert_no_enqueued_jobs only: Shiplog::AnnounceJob do
      shiplog_entries(:csv_change_draft).approve!(by: "ed@example.com")
    end
    assert_no_enqueued_jobs only: Shiplog::AnnounceJob do
      Shiplog::Entry.create!(kind: "feature", subject: shiplog_issues(:export_report), title: "Export", body: "B")
        .approve!(by: "ed@example.com")
    end
  end

  test "editing an approved announcement does not announce it again" do
    approve!
    perform_enqueued_jobs
    clear_enqueued_jobs

    assert_no_enqueued_jobs only: Shiplog::AnnounceJob do
      @entry.update!(body: "A fixed typo")
    end
  end

  test "to_markdown, to_html and to_text give the Markdown, the HTML and the plain text of the body" do
    @entry.update!(body: "Intro with **bold**.\n\n## Highlights\n\n- [Dark mode](/changelog/dark-mode)")

    assert_equal @entry.body, @entry.to_markdown
    assert_includes @entry.to_html, "<strong>bold</strong>"
    assert_includes @entry.to_html, "<h2>Highlights</h2>"
    assert_includes @entry.to_html, %(<a href="/changelog/dark-mode">Dark mode</a>)
    assert_includes @entry.to_text, "Intro with bold."
    assert_includes @entry.to_text, "- Dark mode (/changelog/dark-mode)"
    assert_not_includes @entry.to_text, "**"
  end

  test "the exports use the translation of a configured locale, English otherwise" do
    Shiplog.config.locales = [ :es ]
    approve!
    translate!(body: "## Destacados\n\nTexto **nuevo**")

    assert_equal "## Destacados\n\nTexto **nuevo**", @entry.to_markdown(:es)
    assert_includes @entry.to_html(:es), "<h2>Destacados</h2>"
    assert_includes @entry.to_html(:es), "<strong>nuevo</strong>"
    assert_equal "Destacados\n\nTexto nuevo", @entry.to_text(:es)
    assert_equal @entry.body, @entry.to_markdown
    assert_equal @entry.body, @entry.to_markdown(:fr)
  end

  test "public_url is the absolute page URL, respecting canonical_url" do
    assert_equal "/changelog/2026-10", @entry.public_url

    Shiplog.config.canonical_url = "https://example.com"
    assert_equal "https://example.com/changelog/2026-10", @entry.public_url
  end

  test "unseen_announcements_count counts only approved announcements approved after the given time" do
    assert_equal 0, Shiplog.unseen_announcements_count
    approve!

    assert_equal 1, Shiplog.unseen_announcements_count
    assert_equal 1, Shiplog.unseen_announcements_count(since: 1.hour.ago)
    assert_equal 0, Shiplog.unseen_announcements_count(since: 1.hour.from_now)
  end

  test "unseen_announcements_count ignores drafts and discarded announcements" do
    other = Shiplog::Period.month(Date.new(2026, 9, 1))
    Shiplog::Entry.create!(kind: "announcement", subject: other, title: "September", status: "discarded", released_on: other.ends_on)

    assert_equal 0, Shiplog.unseen_announcements_count
  end

  test "unseen_announcements_count is capped at 99" do
    100.times do |index|
      period = Shiplog::Period.month(Date.new(2000, 1, 1) + index.months)
      Shiplog::Entry.create!(kind: "announcement", subject: period, title: period.title, status: "approved",
        released_on: period.ends_on, approved_at: Time.current, slug: period.starts_on.strftime("%Y-%m"))
    end

    assert_equal 99, Shiplog.unseen_announcements_count
  end

  test "unseen_count does not count announcements" do
    before = Shiplog.unseen_count
    approve!

    assert_equal 1, before
    assert_equal before, Shiplog.unseen_count
    assert_equal 1, Shiplog.unseen_count(since: Time.zone.local(2026, 10, 1))
    assert_equal 0, Shiplog.unseen_count(since: 1.hour.from_now)
  end
end
