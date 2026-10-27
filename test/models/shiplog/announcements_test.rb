require "test_helper"

class Shiplog::AnnouncementsTest < ActiveJob::TestCase
  OCTOBER = Date.new(2026, 10, 15)

  test "draft creates the announcement draft of the month and enqueues its rewrite" do
    entry = nil
    assert_enqueued_jobs 1, only: Shiplog::RewriteEntryJob do
      entry = Shiplog::Announcements.draft(month: OCTOBER)
    end

    period = Shiplog::Period.find_by!(starts_on: Date.new(2026, 10, 1))
    assert entry.announcement?
    assert entry.draft?
    assert_equal period, entry.subject
    assert_equal "2026-10", entry.slug
    assert_equal Date.new(2026, 10, 31), entry.released_on
    assert_equal "October 2026", entry.title
    assert_equal period.body, entry.body
    assert_includes entry.body, "[Dark mode](/changelog/dark-mode)"
    assert_enqueued_with(job: Shiplog::RewriteEntryJob, args: [ entry.id ])
  end

  test "a month without approved entries drafts nothing and creates no period" do
    assert_no_enqueued_jobs do
      assert_nil Shiplog::Announcements.draft(month: Date.new(2026, 9, 10))
    end

    assert_equal 0, Shiplog::Period.count
    assert_equal 0, Shiplog::Entry.where(kind: "announcement").count
  end

  test "draft is idempotent" do
    first = Shiplog::Announcements.draft(month: OCTOBER)

    assert_no_difference -> { Shiplog::Entry.count } do
      assert_nil Shiplog::Announcements.draft(month: Date.new(2026, 10, 1))
    end
    assert_equal 1, Shiplog::Period.count
    assert_equal first, Shiplog::Period.first.announcement
  end

  test "draft is idempotent whatever the status of the existing announcement" do
    Shiplog::Announcements.draft(month: OCTOBER).discard!(reason: "later")

    assert_nil Shiplog::Announcements.draft(month: OCTOBER)
  end

  test "draft does nothing when announcements are off" do
    Shiplog.config.announcements = false

    assert_no_enqueued_jobs do
      assert_nil Shiplog::Announcements.draft(month: OCTOBER)
    end
    assert_equal 0, Shiplog::Period.count
  end

  test "draft works when announcements are published externally" do
    Shiplog.config.announcements = :external

    assert Shiplog::Announcements.draft(month: OCTOBER)
  end

  test "the slug falls back to 2026-10-update when a feature already has the month's slug" do
    shiplog_entries(:dark_mode_feature).update_columns(slug: "2026-10")

    entry = Shiplog::Announcements.draft(month: OCTOBER)

    assert_equal "2026-10-update", entry.slug
  end

  test "a feature titled like a month gets a suffix when approved, keeping the month's slug free" do
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: "m",
      committed_at: Time.current, url: "https://example.com/commit/1")
    feature = Shiplog::Entry.create!(kind: "feature", subject: commit, title: "2026 10", body: "Body")

    feature.approve!(by: "ed@example.com")

    assert_equal "2026-10-2", feature.reload.slug
    assert_equal "2026-10", Shiplog::Announcements.draft(month: OCTOBER).slug
  end

  test "slug_for keeps the plain month slug for the period's own announcement" do
    period = Shiplog::Period.month(OCTOBER)
    assert_equal "2026-10", Shiplog::Announcements.slug_for(period)

    Shiplog::Announcements.draft(month: OCTOBER)
    assert_equal "2026-10", Shiplog::Announcements.slug_for(period)
  end

  test "slug_for goes on to 2026-10-update-2 when the month and its update slug are both taken" do
    shiplog_entries(:dark_mode_feature).update_columns(slug: "2026-10")
    Shiplog::Entry.create!(kind: "change", status: "approved", slug: "2026-10-update", released_on: Date.new(2026, 10, 2), title: "Other",
      subject: Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: "m",
        committed_at: Time.current, url: "https://example.com/c"))

    assert_equal "2026-10-update-2", Shiplog::Announcements.slug_for(Shiplog::Period.month(OCTOBER))
  end

  test "draftable_months are the current and the previous month" do
    assert_equal [ Date.new(2026, 10, 1), Date.new(2026, 9, 1) ], Shiplog::Announcements.draftable_months(Date.new(2026, 10, 27))
    assert_equal [ Date.new(2026, 1, 1), Date.new(2025, 12, 1) ], Shiplog::Announcements.draftable_months(Date.new(2026, 1, 31))

    travel_to Time.zone.local(2026, 3, 31, 12) do
      assert_equal [ Date.new(2026, 3, 1), Date.new(2026, 2, 1) ], Shiplog::Announcements.draftable_months
    end
  end

  test "DraftAnnouncementJob drafts the previous month by default" do
    travel_to Time.zone.local(2026, 11, 2, 9) do
      assert_difference -> { Shiplog::Entry.where(kind: "announcement").count }, 1 do
        Shiplog::DraftAnnouncementJob.perform_now
      end
      assert_nothing_raised { Shiplog::DraftAnnouncementJob.perform_now }
    end

    assert_equal "2026-10", Shiplog::Entry.find_by!(kind: "announcement").slug
  end

  test "DraftAnnouncementJob takes an explicit month" do
    Shiplog::DraftAnnouncementJob.perform_now(Date.new(2026, 10, 1))

    assert_equal 1, Shiplog::Entry.where(kind: "announcement").count
  end
end
