require "test_helper"

class Shiplog::IssueFormTest < ActiveSupport::TestCase
  test "splits sections and maps _No response_ to nil" do
    body = "### Problem\n\nSlow\n\n### Before\n\n_No response_\n\n### After\n\nFast"

    assert_equal({ "problem" => "Slow", "before" => nil, "after" => "Fast" }, Shiplog::IssueForm.parse(body))
  end

  test "returns an empty hash without headings" do
    assert_equal({}, Shiplog::IssueForm.parse("Just some text"))
    assert_equal({}, Shiplog::IssueForm.parse(nil))
  end

  test "ignores headings inside fenced code blocks" do
    body = "### Problem\n\nSee:\n```md\n### Not a heading\n```\n~~~\n### Also not\n~~~\n\n### After\n\nFast"
    result = Shiplog::IssueForm.parse(body)

    assert_equal %w[problem after], result.keys
    assert_includes result["problem"], "### Not a heading"
    assert_includes result["problem"], "### Also not"
  end

  test "normalises keys with parameterize" do
    assert_equal [ "what_s_new" ], Shiplog::IssueForm.parse("### What's New?\n\nx").keys
  end
end
