require "test_helper"
require "rake"

class Shiplog::DraftAnnouncementTaskTest < ActiveJob::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("shiplog:draft_announcement")
    Rake::Task["shiplog:draft_announcement"].reenable
    @month = ENV.delete("MONTH")
  end

  teardown do
    ENV["MONTH"] = @month
    ENV.delete("MONTH") if @month.nil?
  end

  def run_task(month = nil)
    ENV["MONTH"] = month if month
    Rake::Task["shiplog:draft_announcement"].reenable
    out, = capture_io { Rake::Task["shiplog:draft_announcement"].invoke }
    out
  end

  test "it drafts the month given in MONTH and says so" do
    out = run_task("2026-10")

    entry = Shiplog::Entry.find_by!(kind: "announcement")
    assert_equal "2026-10", entry.slug
    assert_includes out, "drafted the 2026-10 announcement (entry #{entry.id})"
    assert_enqueued_jobs 1, only: Shiplog::RewriteEntryJob
  end

  test "it drafts the previous month by default" do
    shiplog_entries(:dark_mode_feature).update_columns(released_on: Date.new(2026, 9, 9))

    travel_to Time.zone.local(2026, 10, 2, 9) do
      assert_includes run_task, "drafted the 2026-09 announcement"
    end
  end

  test "running it again is harmless" do
    run_task("2026-10")

    assert_no_difference -> { Shiplog::Entry.count } do
      assert_includes run_task("2026-10"), "nothing drafted for 2026-10"
    end
  end

  test "a month without approved entries drafts nothing" do
    assert_includes run_task("2026-05"), "nothing drafted for 2026-05"
    assert_equal 0, Shiplog::Entry.where(kind: "announcement").count
  end

  test "it says so when announcements are off" do
    Shiplog.config.announcements = false

    assert_includes run_task("2026-10"), "config.announcements is false"
    assert_equal 0, Shiplog::Entry.where(kind: "announcement").count
  end

  test "a malformed MONTH aborts with a usage message" do
    ENV["MONTH"] = "October"
    Rake::Task["shiplog:draft_announcement"].reenable

    error = assert_raises(SystemExit) { capture_io { Rake::Task["shiplog:draft_announcement"].invoke } }

    assert_equal 1, error.status
  end
end
