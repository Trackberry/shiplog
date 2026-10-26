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

  test "approve! only works from draft" do
    %i[dark_mode_feature typo_change_discarded].each do |name|
      entry = shiplog_entries(name)
      before = entry.attributes
      assert_raises(Shiplog::Entry::InvalidTransition) { entry.approve!(by: "ed@example.com") }
      assert_equal before, entry.reload.attributes
    end
  end

  test "discard! only works from draft" do
    %i[dark_mode_feature typo_change_discarded].each do |name|
      entry = shiplog_entries(name)
      before = entry.attributes
      assert_raises(Shiplog::Entry::InvalidTransition) { entry.discard!(reason: "x") }
      assert_equal before, entry.reload.attributes
    end
  end

  test "restore! only works from discarded" do
    %i[dark_mode_feature csv_change_draft].each do |name|
      assert_raises(Shiplog::Entry::InvalidTransition) { shiplog_entries(name).restore! }
    end
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

  test "an unknown kind or status makes the record invalid" do
    entry = shiplog_entries(:csv_change_draft)
    entry.kind = "bogus"
    assert_not entry.valid?
    entry.kind = "change"
    entry.status = "bogus"
    assert_not entry.valid?
  end

  test "approved feature and change entries require released_on, roadmap entries do not" do
    feature = shiplog_entries(:dark_mode_feature)
    feature.released_on = nil
    assert_not feature.valid?
    assert feature.errors.of_kind?(:released_on, :blank)
    assert shiplog_entries(:bulk_upload_roadmap).valid?
    draft = shiplog_entries(:csv_change_draft)
    assert draft.valid?
  end

  test "a change can become a feature and back, keeping its status" do
    entry = shiplog_entries(:csv_change_draft)
    entry.update!(changelog_kind: "feature")
    assert_equal [ "feature", "draft" ], [ entry.reload.kind, entry.status ]
    entry.update!(changelog_kind: "change")
    assert_equal "change", entry.reload.kind
  end

  test "changelog_kind= ignores roadmap and unknown values" do
    entry = shiplog_entries(:csv_change_draft)
    [ "roadmap", "bogus", "", nil, 3 ].each do |value|
      entry.changelog_kind = value
      assert_equal "change", entry.kind, value.inspect
    end
  end

  test "a roadmap entry cannot change kind" do
    entry = shiplog_entries(:bulk_upload_roadmap)
    entry.changelog_kind = "feature"
    assert_equal "roadmap", entry.kind
    entry.kind = "feature"
    assert_not entry.valid?
    assert entry.errors.of_kind?(:kind, :invalid)
  end

  test "a feature or change entry cannot become a roadmap entry" do
    entry = shiplog_entries(:csv_change_draft)
    entry.kind = "roadmap"
    assert_not entry.valid?
  end

  test "switching to a kind the subject already has is a validation error, not a database error" do
    entry = shiplog_entries(:csv_change_draft)
    Shiplog::Entry.create!(kind: "feature", subject: entry.subject, title: "Other")
    assert_not entry.update(changelog_kind: "feature")
    assert entry.errors.of_kind?(:changelog_kind, :taken)
  end

  test "approved entries are indexed by status then released_on for the changelog and recently shipped queries" do
    indexes = Shiplog::Entry.connection.indexes(:shiplog_entries).map(&:columns)

    assert_includes indexes, %w[status released_on]
  end

  test "search_terms normalises: squished, capped at 100 characters and five words" do
    assert_equal [ "a", "b" ], Shiplog::Entry.search_terms("  a \n b ")
    assert_equal [], Shiplog::Entry.search_terms(nil)
    assert_equal [], Shiplog::Entry.search_terms("   ")
    assert_equal %w[1 2 3 4 5], Shiplog::Entry.search_terms("1 2 3 4 5 6 7")
    assert_equal 100, Shiplog::Entry.search_terms("x" * 150).first.size
  end

  test "search matches title or body with ILIKE and returns everything for a blank query" do
    assert_equal [ shiplog_entries(:dark_mode_feature) ], Shiplog::Entry.search("DARK").to_a
    assert_equal [ shiplog_entries(:dark_mode_feature) ], Shiplog::Entry.search("theme").to_a
    assert_equal Shiplog::Entry.count, Shiplog::Entry.search("  ").count
    assert_empty Shiplog::Entry.search("%")
  end
end
