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
    assert entry.approved?
  end

  test "forced regeneration of an approved entry applies the text and returns it to draft" do
    entry = rewrite(shiplog_entries(:bulk_upload_roadmap), reply, force: true)

    assert_equal "T", entry.title
    assert entry.draft?
    assert_nil entry.approved_at
    assert_nil entry.approved_by
  end

  test "a non-forced rewrite never overwrites an entry approved during the LLM call" do
    entry = shiplog_entries(:csv_change_draft)
    original = entry.title
    Shiplog.config.rewriter = lambda do |_prompt|
      Shiplog::Entry.find(entry.id).approve!(by: "ed")
      reply
    end

    returned = Shiplog::Rewriter.new(entry).call

    assert_same entry, returned
    entry.reload
    assert entry.approved?
    assert_equal original, entry.title
  end

  test "auto-discard never discards an entry approved during the LLM call" do
    entry = shiplog_entries(:csv_change_draft)
    Shiplog.config.rewriter = lambda do |_prompt|
      Shiplog::Entry.find(entry.id).approve!(by: "ed")
      reply(customer_facing: false)
    end

    Shiplog::Rewriter.new(entry).call(force: true)

    assert_not entry.reload.discarded?
  end

  test "call returns the entry on every path" do
    entry = shiplog_entries(:csv_change_draft)
    Shiplog.config.rewriter = ->(_prompt) { reply }
    assert_same entry, Shiplog::Rewriter.new(entry).call
    Shiplog.config.rewriter = ->(_prompt) { "nope" }
    assert_same entry, Shiplog::Rewriter.new(entry).call
    Shiplog.config.rewriter = ->(_prompt) { raise "down" }
    assert_same entry, Shiplog::Rewriter.new(entry).call
    assert_same shiplog_entries(:bulk_upload_roadmap), Shiplog::Rewriter.new(shiplog_entries(:bulk_upload_roadmap)).call
  end

  test "takes the first valid object when the reply contains several" do
    entry = rewrite(shiplog_entries(:csv_change_draft), '{"foo":1} then {"title":"First","body":"B"} and {"title":"Second"}')

    assert_equal "First", entry.title
  end

  test "handles nested braces and braces inside strings" do
    entry = rewrite(shiplog_entries(:csv_change_draft), '{"title":"Use {curly} \\"quotes\\"","body":"a } b","meta":{"x":{"y":1}}}')

    assert_equal 'Use {curly} "quotes"', entry.title
    assert_equal "a } b", entry.body
  end

  test "ignores prose with braces after the JSON" do
    entry = rewrite(shiplog_entries(:csv_change_draft), '{"title":"T","body":"B"} Note: use {placeholders} like } this {')

    assert_equal "T", entry.title
    assert_nil entry.rewrite_error
  end

  test "treats a missing customer_facing as true" do
    entry = rewrite(shiplog_entries(:csv_change_draft), '{"title":"T","body":"B"}')

    assert entry.draft?
    assert_nil entry.rewrite_error
  end

  test "rejects invalid field types" do
    [ '{"title":"","body":"B"}', '{"title":"   ","body":"B"}', '{"title":5}', '{"title":"T","body":5}', '{"title":"T","customer_facing":"yes"}' ].each do |text|
      entry = rewrite(shiplog_entries(:csv_change_draft), text)

      assert_equal "Could not parse rewriter output", entry.rewrite_error, text
      assert_equal "Better CSV validation", entry.title
    end
  end

  test "accepts a null body" do
    entry = rewrite(shiplog_entries(:csv_change_draft), '{"title":"T","body":null}')

    assert_equal "", entry.body.to_s
    assert_nil entry.rewrite_error
  end

  test "strips control characters and squishes the title" do
    entry = rewrite(shiplog_entries(:csv_change_draft), { title: "  A\u0000 \u0007b\n  c ", body: "line1\u0000\nline2\u001b" }.to_json)

    assert_equal "A b c", entry.title
    assert_equal "line1\nline2", entry.body
  end

  test "truncates long titles and bodies on a word boundary" do
    entry = rewrite(shiplog_entries(:csv_change_draft), { title: "word " * 60, body: "sentence " * 400 }.to_json)

    assert_operator entry.title.length, :<=, 120
    assert entry.title.end_with?("…")
    assert_operator entry.body.length, :<=, 2000
    assert entry.body.end_with?("…")
    assert_nil entry.rewrite_error
  end
end
