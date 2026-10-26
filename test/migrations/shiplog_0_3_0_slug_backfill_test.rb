require "test_helper"
require Shiplog::Engine.root.join("db/migrate/20261027000002_shiplog_0_3_0")

class Shiplog030SlugBackfillTest < ActiveSupport::TestCase
  def insert(title:, released_on:, kind: "change", status: "approved", approved_at: Time.current, slug: nil)
    @subject_id = (@subject_id || 40_000) + 1
    now = Time.current
    Shiplog::Entry.insert_all!([ { kind:, status:, subject_type: "Shiplog::Issue", subject_id: @subject_id, title:, body: "Body", slug:,
      released_on:, approved_at:, created_at: now, updated_at: now } ])
    Shiplog::Entry.find_by!(subject_id: @subject_id)
  end

  def migrate_data
    ActiveRecord::Migration.suppress_messages { Shiplog030.new.backfill_slugs }
  end

  setup { Shiplog::Entry.update_all(slug: nil) }

  test "approved features and changes get a slug, the oldest keeping the plain one" do
    newer = insert(title: "Same title", released_on: Date.new(2026, 10, 2))
    older = insert(title: "Same title", released_on: Date.new(2026, 9, 2), kind: "feature")
    underscore = insert(title: "Support for snake_case keys", released_on: Date.new(2026, 9, 3))

    migrate_data

    assert_equal "same-title", older.reload.slug
    assert_equal "same-title-2", newer.reload.slug
    assert_equal "support-for-snake-case-keys", underscore.reload.slug
  end

  test "drafts, discarded and roadmap entries stay without a slug, and existing slugs are kept" do
    draft = insert(title: "A draft", released_on: nil, status: "draft")
    roadmap = insert(title: "Roadmap thing", released_on: nil, kind: "roadmap")
    kept = insert(title: "Kept", released_on: Date.new(2026, 9, 1), slug: "my-own-slug")

    migrate_data

    assert_nil draft.reload.slug
    assert_nil roadmap.reload.slug
    assert_equal "my-own-slug", kept.reload.slug
  end

  test "an empty title falls back to entry-<id> and a taken slug is skipped" do
    insert(title: "Taken", released_on: Date.new(2026, 9, 1), slug: "taken")
    blank = insert(title: "!!!", released_on: Date.new(2026, 9, 2))
    clash = insert(title: "Taken", released_on: Date.new(2026, 9, 3))

    migrate_data

    assert_equal "entry-#{blank.id}", blank.reload.slug
    assert_equal "taken-2", clash.reload.slug
  end

  test "it agrees with the model's slug generation" do
    title = "Crème brûlée_mode — now with “quotes”!"
    entry = insert(title:, released_on: Date.new(2026, 9, 1))
    migrate_data
    migrated = entry.reload.slug

    entry.update_columns(slug: nil)
    assert_equal migrated, entry.ensure_slug!
  end

  test "a long title is cut at 80 characters without a trailing dash" do
    entry = insert(title: "word " * 40, released_on: Date.new(2026, 9, 1))
    migrate_data
    assert_operator entry.reload.slug.length, :<=, 80
    assert_not entry.slug.end_with?("-")
  end
end
