require "test_helper"

class Shiplog::Admin::RewritesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "regenerate enqueues a forced rewrite" do
    entry = shiplog_entries(:dark_mode_feature)
    assert_enqueued_with(job: Shiplog::RewriteEntryJob, args: [ entry.id, { force: true } ]) do
      post "/admin/shiplog/entries/#{entry.id}/rewrite"
    end
    assert_redirected_to "/admin/shiplog/entries/#{entry.id}/edit"
  end
end
