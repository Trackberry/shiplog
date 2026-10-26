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
end
