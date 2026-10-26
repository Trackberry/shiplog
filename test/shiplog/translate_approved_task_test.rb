require "test_helper"
require "rake"

class Shiplog::TranslateApprovedTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("shiplog:translate_approved")
    Rake::Task["shiplog:translate_approved"].reenable
    Shiplog.config.locales = [ :es, :fr ]
    Shiplog.config.rewriter = ->(_prompt) { '{"title":"Titulo","body":"Texto"}' }
    @approved = Shiplog::Entry.approved.order(:id).to_a
    assert_operator @approved.size, :>=, 3
    clear_enqueued_jobs
  end

  def run_task(env = {})
    Rake::Task["shiplog:translate_approved"].reenable
    env.each { |key, value| ENV[key] = value }
    out, = capture_io { Rake::Task["shiplog:translate_approved"].invoke }
    out
  ensure
    env.each_key { |key| ENV.delete(key) }
  end

  def enqueued_pairs
    enqueued_jobs.select { |job| job["job_class"] == "Shiplog::TranslateEntryJob" }.map do |job|
      [ job["arguments"].first["_aj_globalid"][%r{/(\d+)\z}, 1].to_i, job["arguments"].second ]
    end
  end

  def translate!(entry, locale, digest: entry.translation_source_digest)
    entry.translations.create!(locale:, title: "T", body: "B", source_digest: digest)
  end

  test "the tasks are defined once, though both engines load the file" do
    assert_equal 1, Rake::Task["shiplog:translate_approved"].actions.size
    assert_equal 1, Rake::Task["shiplog:backfill_slugs"].actions.size
  end

  test "it enqueues a job for every approved entry and locale without a translation, and prints the counts" do
    out = run_task

    assert_equal @approved.product([ "es", "fr" ]).map { |entry, locale| [ entry.id, locale ] }.sort, enqueued_pairs.sort
    assert_match(/#{@approved.size} approved entries/, out)
    assert_match(/es: #{@approved.size} enqueued, 0 current/, out)
    assert_match(/fr: #{@approved.size} enqueued, 0 current/, out)
  end

  test "it skips what has a current translation, and enqueues stale or missing ones" do
    first, second = @approved
    translate!(first, "es")
    translate!(second, "es", digest: "stale")
    translate!(first, "fr")

    out = run_task

    pairs = enqueued_pairs
    assert_not_includes pairs, [ first.id, "es" ]
    assert_not_includes pairs, [ first.id, "fr" ]
    assert_includes pairs, [ second.id, "es" ]
    assert_includes pairs, [ second.id, "fr" ]
    assert_equal @approved.size * 2 - 2, pairs.size
    assert_match(/es: #{@approved.size - 1} enqueued, 1 current/, out)
    assert_match(/fr: #{@approved.size - 1} enqueued, 1 current/, out)
  end

  test "drafts and discarded entries are left alone" do
    run_task
    ids = enqueued_pairs.map(&:first).uniq
    assert_equal @approved.map(&:id).sort, ids.sort
  end

  test "it is idempotent: once the jobs ran, a second run enqueues nothing" do
    run_task
    perform_enqueued_jobs
    assert_equal @approved.size * 2, Shiplog::EntryTranslation.count

    clear_enqueued_jobs
    out = run_task

    assert_empty enqueued_pairs
    assert_match(/es: 0 enqueued, #{@approved.size} current/, out)
  end

  test "it enqueues in batches of BATCH_SIZE, all of them" do
    out = run_task("BATCH_SIZE" => "1")
    assert_equal @approved.size * 2, enqueued_pairs.size

    queries = sql_statements { Shiplog::Entry.enqueue_missing_translations(batch_size: 1) }.grep(/FROM "shiplog_entries"/)
    assert_operator queries.size, :>=, @approved.size, "one query per batch"
    assert_match(/enqueued/, out)
  end

  test "it says so and enqueues nothing without locales" do
    Shiplog.config.locales = []
    out = run_task
    assert_empty enqueued_pairs
    assert_match(/config.locales is empty/, out)
  end

  test "it says so and enqueues nothing without a rewriter" do
    Shiplog.config.rewriter = nil
    out = run_task
    assert_empty enqueued_pairs
    assert_match(/config.rewriter/, out)
  end

  test "a locale is translated only once an entry has none, not per run" do
    run_task
    perform_enqueued_jobs
    clear_enqueued_jobs
    @approved.first.translations.where(locale: "fr").delete_all
    run_task
    assert_equal [ [ @approved.first.id, "fr" ] ], enqueued_pairs
  end

  def enqueued_area_jobs = enqueued_jobs.select { |job| job["job_class"] == "Shiplog::TranslateAreaJob" }

  test "it also enqueues a job for areas missing a translation in any configured locale" do
    missing = Shiplog::Area.create!(name: "Billing")
    partial = Shiplog::Area.create!(name: "Reports")
    done = Shiplog::Area.create!(name: "Labels")
    partial.update_columns(name_translations: { "es" => "Informes" })
    done.update_columns(name_translations: { "es" => "Etiquetas", "fr" => "Etiquettes" })
    clear_enqueued_jobs

    out = run_task

    ids = enqueued_area_jobs.map { |job| job["arguments"].first["_aj_globalid"][%r{/(\d+)\z}, 1].to_i }
    assert_equal [ missing.id, partial.id ].sort, ids.sort
    assert_match(/2 areas/, out)
  end

  test "it enqueues no area jobs without locales or without a rewriter" do
    Shiplog::Area.create!(name: "Billing")
    clear_enqueued_jobs
    Shiplog.config.locales = []
    run_task
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = nil
    run_task

    assert_empty enqueued_area_jobs
  end
end
