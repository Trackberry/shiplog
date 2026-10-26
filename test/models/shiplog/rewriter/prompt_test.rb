require "test_helper"

class Shiplog::Rewriter::PromptTest < ActiveSupport::TestCase
  setup do
    Shiplog.config.product_name = "Trackberry"
    Shiplog.config.audience = "produce importers"
  end

  test "includes configuration, source text and the JSON instruction" do
    entry = shiplog_entries(:csv_change_draft)
    text = Shiplog::Rewriter::Prompt.new(entry).to_s

    assert_includes text, "Trackberry"
    assert_includes text, "produce importers"
    assert_includes text, Shiplog.config.tone
    assert_includes text, entry.subject.title
    assert_includes text, entry.subject.body
    assert_includes text, "Reply with JSON only"
    assert_includes text, "small change"
  end

  test "feature prompts include form sections, child issues and linked pull requests" do
    issue = shiplog_issues(:bulk_upload)
    issue.update!(body: "### Problem\n\nSlow imports\n\n### After\n\nFast imports")
    entry = Shiplog::Entry.new(kind: "feature", subject: issue)

    text = Shiplog::Rewriter::Prompt.new(entry).to_s

    assert_includes text, "Slow imports"
    assert_includes text, "Fast imports"
    assert_includes text, "CSV import"
    assert_includes text, "CSV validation"
    assert_includes text, "Validate CSV headers"
    assert_includes text, "shipped feature"
  end

  test "uses the configured prompt builder" do
    received = nil
    Shiplog.config.prompt_builder = ->(kind:, context:) { received = [ kind, context ]; "CUSTOM" }
    entry = shiplog_entries(:bulk_upload_roadmap)

    assert_equal "CUSTOM", Shiplog::Rewriter::Prompt.new(entry).to_s
    assert_equal "roadmap", received.first
    assert_includes received.last[:title], "Bulk upload"
  end
end
