require "test_helper"
require "rake"

class Shiplog::BackfillSlugsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("shiplog:backfill_slugs")
    Rake::Task["shiplog:backfill_slugs"].reenable
  end

  def run_task
    out, = capture_io { Rake::Task["shiplog:backfill_slugs"].invoke }
    out
  end

  test "it gives approved changelog entries without a slug one and reports the count" do
    shiplog_entries(:dark_mode_feature).update_columns(slug: nil)
    assert_match(/1 entry/, run_task)
    assert_equal "dark-mode", shiplog_entries(:dark_mode_feature).reload.slug
  end

  test "it is idempotent" do
    assert_match(/0 entries/, run_task)
    assert_equal "dark-mode", shiplog_entries(:dark_mode_feature).reload.slug
  end
end
