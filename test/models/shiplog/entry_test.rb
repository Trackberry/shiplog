require "test_helper"

class Shiplog::EntryTest < ActiveSupport::TestCase
  test "approve! sets status, approved_at, approved_by and released_on default" do
    entry = shiplog_entries(:csv_change_draft)
    travel_to Time.zone.local(2026, 10, 1) do
      entry.approve!(by: "ed@example.com")
    end
    assert entry.approved?
    assert_equal "ed@example.com", entry.approved_by
    assert_equal Date.new(2026, 10, 1), entry.released_on
  end

  test "approve! keeps an existing released_on" do
    entry = shiplog_entries(:csv_change_draft)
    entry.update!(released_on: Date.new(2026, 9, 1))
    entry.approve!(by: "ed@example.com")
    assert_equal Date.new(2026, 9, 1), entry.released_on
  end

  test "discard! and restore!" do
    entry = shiplog_entries(:csv_change_draft)
    entry.discard!(reason: "dup")
    assert entry.discarded?
    entry.restore!
    assert entry.draft?
    assert_nil entry.discard_reason
  end

  test "source_changed? compares digest of subject title and body" do
    entry = shiplog_entries(:csv_change_draft)
    entry.update!(source_digest: Shiplog::Entry.digest_for(entry.subject))
    refute entry.source_changed?
    entry.subject.update!(title: "Something else")
    assert entry.source_changed?
  end

  test "digest_for works for commits through title and body" do
    commit = shiplog_commits(:typo_fix)
    assert_equal "fix: correct typo in invoice email", commit.title
    assert_equal "The subject line misspelled the word invoice.", commit.body
    assert_equal Digest::SHA256.hexdigest("#{commit.title}\n#{commit.body}"), Shiplog::Entry.digest_for(commit)
  end

  test "one entry per subject and kind" do
    existing = shiplog_entries(:csv_change_draft)
    duplicate = Shiplog::Entry.new(kind: "change", subject: existing.subject)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "fixtures cover every status" do
    assert_equal %w[approved discarded draft], Shiplog::Entry.distinct.pluck(:status).sort
  end
end
