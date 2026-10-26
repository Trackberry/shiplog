require "test_helper"

class Shiplog::RewriterTest < ActiveSupport::TestCase
  def reply(customer_facing: true) = "Sure!\n```json\n{\"title\":\"T\",\"body\":\"B\",\"customer_facing\":#{customer_facing}}\n```"

  def rewrite(entry, text, **options)
    Shiplog.config.rewriter = ->(_prompt) { text }
    Shiplog::Rewriter.new(entry).call(**options)
    entry.reload
  end

  test "parses JSON wrapped in prose and fences" do
    entry = rewrite(shiplog_entries(:csv_change_draft), reply)

    assert_equal "T", entry.title
    assert_equal "B", entry.body
    assert entry.rewritten_at
    assert_nil entry.rewrite_error
    assert_equal Shiplog::Entry.digest_for(entry.subject), entry.source_digest
    assert entry.draft?
  end

  test "passes the prompt string to the rewriter" do
    received = nil
    Shiplog.config.rewriter = ->(prompt) { received = prompt; reply }
    Shiplog::Rewriter.new(shiplog_entries(:csv_change_draft)).call

    assert_kind_of String, received
  end

  test "clears a previous rewrite error" do
    entry = shiplog_entries(:csv_change_draft)
    entry.update!(rewrite_error: "boom")

    assert_nil rewrite(entry, reply).rewrite_error
  end

  test "discards change entries that are not customer facing" do
    entry = rewrite(shiplog_entries(:csv_change_draft), reply(customer_facing: false))

    assert entry.discarded?
    assert_equal "Not customer-facing (suggested by AI)", entry.discard_reason
  end

  test "keeps roadmap and feature entries as drafts when not customer facing" do
    roadmap = rewrite(shiplog_entries(:soon_item_roadmap), reply(customer_facing: false))
    feature = Shiplog::Entry.create!(kind: "feature", subject: shiplog_issues(:export_report))
    feature = rewrite(feature, reply(customer_facing: false))

    assert roadmap.draft?
    assert feature.draft?
  end

  test "keeps the original text and records an error when output is unparseable" do
    entry = rewrite(shiplog_entries(:csv_change_draft), "no json here")

    assert_equal "Better CSV validation", entry.title
    assert_equal "Could not parse rewriter output", entry.rewrite_error
  end

  test "records an error for malformed JSON" do
    entry = rewrite(shiplog_entries(:csv_change_draft), "{not json}")

    assert_equal "Could not parse rewriter output", entry.rewrite_error
  end

  test "falls back to the source text for a new entry when the rewriter fails" do
    issue = shiplog_issues(:export_report)
    entry = Shiplog::Entry.create!(kind: "feature", subject: issue)
    entry = rewrite(entry, "nope")

    assert_equal issue.title, entry.title
    assert_equal issue.body, entry.body
    assert_equal Shiplog::Entry.digest_for(issue), entry.source_digest
  end

  test "records the message when the rewriter raises" do
    Shiplog.config.rewriter = ->(_prompt) { raise "model down" }
    entry = shiplog_entries(:csv_change_draft)

    assert_nothing_raised { Shiplog::Rewriter.new(entry).call }
    assert_equal "model down", entry.reload.rewrite_error
  end

  test "records an error without a rewriter" do
    Shiplog.config.rewriter = nil
    entry = shiplog_entries(:csv_change_draft)
    Shiplog::Rewriter.new(entry).call

    assert_equal "No rewriter configured", entry.reload.rewrite_error
  end

  test "does not touch approved entries unless forced" do
    entry = shiplog_entries(:bulk_upload_roadmap)

    assert_equal "Upload many shipments at once", rewrite(entry, reply).title
    assert_equal "T", rewrite(entry, reply, force: true).title
    assert entry.approved?
  end
end
