require "test_helper"
require "yaml"

class Shiplog::IssueFormTemplateTest < ActiveSupport::TestCase
  PATHS = [
    File.expand_path("../../../lib/generators/shiplog/install/templates/shiplog-feature.yml", __dir__),
    File.expand_path("../../../.github/ISSUE_TEMPLATE/shiplog-feature.yml", __dir__)
  ].freeze

  test "the dogfooded copy is identical to the generator template" do
    assert_equal File.read(PATHS.first), File.read(PATHS.last)
  end

  test "metadata" do
    form = YAML.safe_load_file(PATHS.first)

    assert_equal "Customer-facing feature", form["name"]
    assert_equal [ "public" ], form["labels"]
    assert_equal %w[problem before after], form["body"].map { |field| field["id"] }
    assert_equal %w[Problem Before After], form["body"].map { |field| field["attributes"]["label"] }
    assert_equal [ "textarea" ], form["body"].map { |field| field["type"] }.uniq
  end

  test "a body rendered from the form parses into sections" do
    form = YAML.safe_load_file(PATHS.first)
    answers = { "problem" => "Hard to find invoices.", "before" => "_No response_", "after" => "Search by number." }
    body = form["body"].map { |field| "### #{field["attributes"]["label"]}\n\n#{answers[field["id"]]}" }.join("\n\n")

    assert_equal({ "problem" => "Hard to find invoices.", "before" => nil, "after" => "Search by number." },
      Shiplog::IssueForm.parse(body))
  end
end
