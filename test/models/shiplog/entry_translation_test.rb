require "test_helper"

class Shiplog::EntryTranslationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Shiplog.config.locales = [ :es, :fr ]
    @entry = shiplog_entries(:dark_mode_feature)
  end

  def translate!(entry, locale: "es", title: "Modo oscuro", body: "Cambia a un tema oscuro.", **attributes)
    entry.translations.create!(locale:, title:, body:, source_digest: entry.translation_source_digest, **attributes)
  end

  test "a translation belongs to an entry, one per locale" do
    translate!(@entry)

    duplicate = @entry.translations.build(locale: "es", title: "x", body: "y", source_digest: "z")
    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "needs a locale, a title and a digest" do
    translation = Shiplog::EntryTranslation.new(entry: @entry)

    assert_not translation.valid?
    assert_equal %i[locale title source_digest].sort, translation.errors.attribute_names.sort
  end

  test "edited_by_admin defaults to false" do
    assert_equal false, translate!(@entry).edited_by_admin
  end

  test "destroying the entry destroys its translations, and the database cascades" do
    translate!(@entry)
    translate!(@entry, locale: "fr")
    assert_difference -> { Shiplog::EntryTranslation.count }, -2 do
      @entry.destroy
    end

    other = shiplog_entries(:later_item_roadmap)
    translate!(other)
    assert_difference -> { Shiplog::EntryTranslation.count }, -1 do
      Shiplog::Entry.where(id: other.id).delete_all
    end
  end

  test "stale? compares the digest with the entry's current English text" do
    translation = translate!(@entry)
    assert_not translation.stale?

    @entry.update_columns(title: "Dark mode!")
    assert translation.reload.stale?
  end

  test "display_title and display_body give the translation under a configured locale" do
    translate!(@entry)

    I18n.with_locale(:es) do
      assert_equal "Modo oscuro", @entry.display_title
      assert_equal "Cambia a un tema oscuro.", @entry.display_body
    end
  end

  test "display text is English under the default locale, an unconfigured one, and when the translation is missing or stale" do
    translation = translate!(@entry)

    assert_equal "Dark mode", @entry.display_title
    assert_equal "Switch to a dark theme.", @entry.display_body
    with_extra_locale(:de) do
      I18n.with_locale(:de) { assert_equal "Dark mode", @entry.display_title }
    end
    with_extra_locale(:fr) do
      I18n.with_locale(:fr) { assert_equal "Dark mode", @entry.display_title } # configured, but no French translation
    end
    I18n.with_locale(:es) do
      translation.update_columns(source_digest: "old")
      assert_equal "Dark mode", @entry.reload.display_title
      assert_equal "Switch to a dark theme.", @entry.display_body
    end
  end

  test "an empty translated body shows the English one" do
    translate!(@entry, body: "")

    I18n.with_locale(:es) { assert_equal @entry.body, @entry.display_body }
  end

  test "translations are preloaded for the current locale only" do
    translate!(@entry)
    translate!(@entry, locale: "fr", title: "Mode sombre")
    entries = Shiplog::Entry.where(id: @entry.id).to_a

    I18n.with_locale(:es) do
      Shiplog::Entry.preload_translations(entries)
      assert entries.first.translations.loaded?
      assert_equal [ "es" ], entries.first.translations.map(&:locale)
      assert_equal 0, count_queries { entries.first.display_title; entries.first.display_body }
    end
  end

  test "preloading does nothing, and runs no query, under a locale that is not translated" do
    entries = Shiplog::Entry.where(id: @entry.id).to_a

    assert_equal 0, count_queries { Shiplog::Entry.preload_translations(entries) }
    assert_not entries.first.translations.loaded?
  end

  test "approving enqueues one translation per configured locale" do
    draft = shiplog_entries(:csv_change_draft)

    assert_enqueued_jobs 2, only: Shiplog::TranslateEntryJob do
      draft.approve!(by: "ed@example.com")
    end
    assert_enqueued_with(job: Shiplog::TranslateEntryJob, args: [ draft, :es ])
    assert_enqueued_with(job: Shiplog::TranslateEntryJob, args: [ draft, :fr ])
  end

  test "approving a roadmap entry enqueues translations too" do
    roadmap = shiplog_entries(:soon_item_roadmap)

    assert_enqueued_jobs 2, only: Shiplog::TranslateEntryJob do
      roadmap.approve!(by: "ed@example.com")
    end
  end

  test "editing the English title or body of an approved entry enqueues one translation per locale" do
    assert_enqueued_jobs 2, only: Shiplog::TranslateEntryJob do
      @entry.update!(title: "Dark mode for everyone")
    end
    assert_enqueued_jobs 2, only: Shiplog::TranslateEntryJob do
      @entry.update!(body: "A dark theme.")
    end
    assert_enqueued_jobs 2, only: Shiplog::TranslateEntryJob do
      shiplog_entries(:bulk_upload_roadmap).update!(body: "Import a spreadsheet.")
    end
  end

  test "other edits, edits of drafts and discarded entries, and rewrites enqueue nothing" do
    assert_no_enqueued_jobs only: Shiplog::TranslateEntryJob do
      @entry.update!(released_on: Date.new(2026, 10, 1))
      @entry.update!(title: @entry.title)
      shiplog_entries(:csv_change_draft).update!(title: "Edited draft")
      shiplog_entries(:typo_change_discarded).update!(title: "Edited discarded")
      @entry.update!(status: "draft", title: "Unpublished and rewritten") # a forced rewrite unpublishes
    end
  end

  test "nothing is enqueued without configured locales" do
    Shiplog.config.locales = []

    assert_no_enqueued_jobs only: Shiplog::TranslateEntryJob do
      shiplog_entries(:csv_change_draft).approve!(by: "ed@example.com")
      @entry.update!(title: "Changed")
    end
  end

  test "display_body falls back to the English body when the translation's body is blank" do
    translate!(@entry, body: "")
    assert_equal @entry.body, @entry.display_body(:es)
    assert_equal @entry.body, @entry.reload.display_body(:es)
    assert_equal "Modo oscuro", @entry.display_title(:es)
  end

  test "display_body is blank when both bodies are blank" do
    @entry.update_columns(body: nil)
    translate!(@entry, body: "")
    assert_empty @entry.reload.display_body(:es).to_s
  end
end
