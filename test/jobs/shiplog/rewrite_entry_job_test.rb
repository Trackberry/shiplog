require "test_helper"

class Shiplog::RewriteEntryJobTest < ActiveJob::TestCase
  test "rewrites the entry" do
    Shiplog.config.rewriter = ->(_prompt) { '{"title":"T","body":"B","customer_facing":true}' }
    entry = shiplog_entries(:csv_change_draft)

    Shiplog::RewriteEntryJob.perform_now(entry.id)

    assert_equal "T", entry.reload.title
  end

  test "passes force through" do
    Shiplog.config.rewriter = ->(_prompt) { '{"title":"T","body":"B","customer_facing":true}' }
    entry = shiplog_entries(:bulk_upload_roadmap)

    Shiplog::RewriteEntryJob.perform_now(entry.id, force: true)

    assert_equal "T", entry.reload.title
  end

  test "ignores entries that no longer exist" do
    assert_nothing_raised { Shiplog::RewriteEntryJob.perform_now(0) }
  end
end
