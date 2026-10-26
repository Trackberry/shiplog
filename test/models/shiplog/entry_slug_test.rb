require "test_helper"

class Shiplog::EntrySlugTest < ActiveSupport::TestCase
  def draft(title:, kind: "change", id: nil)
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: title.to_s,
      committed_at: Time.current, url: "https://github.com/x/y/commit/1")
    entry = Shiplog::Entry.create!(kind:, subject: commit, title:, body: "Body")
    entry.update_columns(id:) if id
    entry
  end

  test "approving a change or a feature generates a slug from the title" do
    entry = draft(title: "Better CSV validation!")
    entry.approve!(by: "ed@example.com")
    assert_equal "better-csv-validation", entry.reload.slug

    feature = draft(title: "Dark Mode, finally", kind: "feature")
    feature.approve!(by: "ed@example.com")
    assert_equal "dark-mode-finally", feature.reload.slug
  end

  test "slugs only contain a-z, 0-9 and single dashes, whatever the title" do
    {
      "Support for snake_case keys" => "support-for-snake-case-keys",
      "__init__ and  -- dashes --" => "init-and-dashes",
      "Crème brûlée_mode" => "creme-brulee-mode"
    }.each do |title, expected|
      entry = draft(title:)
      entry.approve!(by: "ed@example.com")
      assert_equal expected, entry.reload.slug, title
      assert_match(/\A[a-z0-9]+(-[a-z0-9]+)*\z/, entry.slug)
    end
  end

  test "roadmap entries get no slug" do
    entry = draft(title: "Soon thing", kind: "roadmap")
    entry.approve!(by: "ed@example.com")
    assert_nil entry.reload.slug
  end

  test "drafts have no slug" do
    assert_nil draft(title: "Nothing yet").slug
  end

  test "a blank parameterized title falls back to entry-<id>" do
    entry = draft(title: "!!! ???")
    entry.approve!(by: "ed@example.com")
    assert_equal "entry-#{entry.id}", entry.reload.slug

    nameless = draft(title: nil)
    nameless.approve!(by: "ed@example.com")
    assert_equal "entry-#{nameless.id}", nameless.reload.slug
  end

  test "the slug is capped at 80 characters" do
    entry = draft(title: "word " * 40)
    entry.approve!(by: "ed@example.com")
    assert_operator entry.reload.slug.length, :<=, 80
    assert_not entry.slug.end_with?("-")
  end

  test "duplicate titles get -2, -3 suffixes, also at the length cap" do
    slugs = Array.new(3) { draft(title: "Same title").tap { |entry| entry.approve!(by: "ed@example.com") }.reload.slug }
    assert_equal %w[same-title same-title-2 same-title-3], slugs

    long = Array.new(2) { draft(title: "a" * 100).tap { |entry| entry.approve!(by: "ed@example.com") }.reload.slug }
    assert_equal 80, long.first.length
    assert_equal 80, long.last.length
    assert_equal 2, long.uniq.size
    assert long.last.end_with?("-2")
  end

  test "the slug survives title edits and re-approval" do
    entry = draft(title: "First title")
    entry.approve!(by: "ed@example.com")
    entry.update!(title: "A completely new title")
    assert_equal "first-title", entry.reload.slug

    entry.update!(status: "draft")
    entry.approve!(by: "ed@example.com")
    assert_equal "first-title", entry.reload.slug
  end

  test "a slug taken between the check and the write is retried with a fresh one" do
    entry = draft(title: "Dark mode")
    calls = 0
    # The first check does not see the fixture's "dark-mode" (as if it were committed a moment later), so the
    # unique index rejects the write.
    entry.define_singleton_method(:generate_slug) do
      calls += 1
      calls == 1 ? "dark-mode" : super()
    end
    entry.approve!(by: "ed@example.com")
    assert_equal "dark-mode-2", entry.reload.slug
    assert_equal 2, calls
    assert_predicate entry, :approved?
  end

  test "the slug is unique in the database" do
    first = draft(title: "One")
    first.update_columns(slug: "taken")
    second = draft(title: "Two")
    assert_raises(ActiveRecord::RecordNotUnique) { second.update_columns(slug: "taken") }
  end

  test "ensure_slug! fills an approved entry once and leaves others alone" do
    entry = shiplog_entries(:dark_mode_feature)
    entry.update_columns(slug: nil)
    assert_equal "dark-mode", entry.ensure_slug!
    assert_equal "dark-mode", entry.reload.slug
    assert_equal "dark-mode", entry.ensure_slug!

    assert_nil shiplog_entries(:csv_change_draft).ensure_slug!
    assert_nil shiplog_entries(:bulk_upload_roadmap).ensure_slug!
  end

  test "ensure_slug! never overwrites a slug another process wrote in the meantime" do
    entry = shiplog_entries(:dark_mode_feature)
    entry.update_columns(slug: nil)
    stale = Shiplog::Entry.find(entry.id)
    entry.update_columns(slug: "written-elsewhere")

    assert_equal "written-elsewhere", stale.ensure_slug!
    assert_equal "written-elsewhere", entry.reload.slug
  end

  test "backfill_slugs gives approved changelog entries without a slug one, oldest first" do
    older = draft(title: "Dark mode")
    older.update_columns(status: "approved", released_on: Date.new(2026, 8, 1), approved_at: Time.current)
    shiplog_entries(:dark_mode_feature).update_columns(slug: nil)
    shiplog_entries(:csv_change_draft).update_columns(slug: nil)

    assert_equal 2, Shiplog::Entry.backfill_slugs

    assert_equal "dark-mode", older.reload.slug, "the oldest entry gets the plain slug"
    assert_equal "dark-mode-2", shiplog_entries(:dark_mode_feature).reload.slug
    assert_nil shiplog_entries(:csv_change_draft).reload.slug
    assert_nil shiplog_entries(:bulk_upload_roadmap).reload.slug
    assert_equal 0, Shiplog::Entry.backfill_slugs
  end
end
