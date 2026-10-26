require "test_helper"

class Shiplog::EntryNeighboursTest < ActiveSupport::TestCase
  def publish(title, released_on, approved_at: Time.current)
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: title,
      committed_at: Time.current, url: "https://github.com/x/y/commit/1")
    Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title:, body: "Body", released_on:, approved_at:)
      .tap(&:ensure_slug!)
  end

  test "neighbours follow the changelog order: released_on, approved_at, id" do
    oldest = publish("Oldest", Date.new(2026, 8, 1))
    same_day_first = publish("Same day first", Date.new(2026, 9, 1), approved_at: Time.zone.local(2026, 9, 1, 9))
    same_day_second = publish("Same day second", Date.new(2026, 9, 1), approved_at: Time.zone.local(2026, 9, 1, 10))
    dark = shiplog_entries(:dark_mode_feature)

    assert_equal [ same_day_second, oldest ].map(&:title), [ same_day_first.newer_changelog_entry, same_day_first.older_changelog_entry ].map(&:title)
    assert_equal dark, same_day_second.newer_changelog_entry
    assert_nil dark.newer_changelog_entry
    assert_equal same_day_second, dark.older_changelog_entry
    assert_nil oldest.older_changelog_entry
  end

  test "drafts, discarded and roadmap entries are never neighbours" do
    dark = shiplog_entries(:dark_mode_feature)
    shiplog_entries(:csv_change_draft).update_columns(released_on: Date.new(2026, 10, 20))
    assert_nil dark.newer_changelog_entry
    assert_nil dark.older_changelog_entry
  end

  test "an entry without approved_at sorts like the list does (first within its day)" do
    dark = shiplog_entries(:dark_mode_feature)
    nil_approved = publish("No approval time", dark.released_on, approved_at: nil)

    assert_equal nil_approved, dark.newer_changelog_entry
    assert_equal dark, nil_approved.older_changelog_entry
  end
end
