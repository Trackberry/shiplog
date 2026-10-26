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

  GRAPHQL = "https://api.github.com/graphql".freeze
  IMAGE = "https://private-user-images.githubusercontent.com/1/abc.png?jwt=x".freeze

  def stub_screenshot
    Shiplog.config.github_token = "tok"
    Shiplog.config.rewriter = ->(_prompt) { '{"title":"T","body":"B","customer_facing":true}' }
    stub_request(:post, GRAPHQL).to_return(body: { data: { node: { bodyHTML: %(<img src="#{IMAGE}">) } } }.to_json)
    stub_request(:get, IMAGE).to_return(body: image_bytes(:png))
  end

  test "attaches the screenshots of the GitHub body to the draft it wrote" do
    stub_screenshot
    entry = shiplog_entries(:csv_change_draft)

    Shiplog::RewriteEntryJob.perform_now(entry.id)

    assert_equal "T", entry.reload.title
    assert_equal 1, entry.ordered_images.size
  end

  test "a failing image fetch never fails the draft" do
    stub_screenshot
    stub_request(:post, GRAPHQL).to_return(status: 500)
    entry = shiplog_entries(:csv_change_draft)

    assert_nothing_raised { Shiplog::RewriteEntryJob.perform_now(entry.id) }

    entry.reload
    assert_equal "T", entry.title
    assert_nil entry.rewrite_error
    assert_empty entry.ordered_images
  end

  test "an approved entry is not rewritten and its images are not touched" do
    stub_screenshot
    entry = shiplog_entries(:dark_mode_feature)

    Shiplog::RewriteEntryJob.perform_now(entry.id)

    assert_equal "Dark mode", entry.reload.title
    assert_not_requested :post, GRAPHQL
  end

  test "a forced regeneration fetches images only when the entry has none" do
    stub_screenshot
    entry = shiplog_entries(:dark_mode_feature)

    Shiplog::RewriteEntryJob.perform_now(entry.id, force: true)
    entry.reload
    assert entry.draft?
    assert_equal 1, entry.ordered_images.size

    Shiplog::RewriteEntryJob.perform_now(entry.id, force: true)
    assert_requested :post, GRAPHQL, times: 1
    assert_equal 1, entry.reload.ordered_images.size
  end

  test "a forced regeneration of an approved entry that has images leaves them alone" do
    stub_screenshot
    entry = shiplog_entries(:dark_mode_feature)
    entry.add_images([ { io: StringIO.new(image_bytes(:gif)), filename: "mine.gif", content_type: "image/gif" } ])

    Shiplog::RewriteEntryJob.perform_now(entry.id, force: true)

    assert_not_requested :post, GRAPHQL
    assert_equal [ "mine.gif" ], entry.reload.ordered_images.map { |image| image.blob.filename.to_s }
  end
end
