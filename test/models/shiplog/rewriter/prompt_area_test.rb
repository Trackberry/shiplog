require "test_helper"

class Shiplog::Rewriter::PromptAreaTest < ActiveSupport::TestCase
  def prompt(entry = shiplog_entries(:csv_change_draft)) = Shiplog::Rewriter::Prompt.new(entry).to_s

  test "asks for an area in the JSON reply" do
    text = prompt

    assert_includes text, %("area")
    assert_includes text, "1–3 words"
  end

  test "lists the existing areas as data, before the source block" do
    Shiplog::Area.create!(name: "Billing")
    Shiplog::Area.create!(name: "Shipping & Tracking")
    text = prompt

    assert_includes text, "Billing"
    assert_includes text, "Shipping & Tracking"
    assert_includes text, "Existing areas"
    assert_operator text.index("Billing"), :<, text.index("<source>")
    assert text.rstrip.end_with?("</source>")
  end

  test "lists the areas in their admin order" do
    Shiplog::Area.create!(name: "Zeta")
    Shiplog::Area.create!(name: "Alpha")
    text = prompt

    assert_operator text.index("Zeta"), :<, text.index("Alpha")
  end

  test "asks to reuse an existing area where possible" do
    Shiplog::Area.create!(name: "Billing")

    assert_includes prompt, "Reuse an existing area"
  end

  test "past max_areas the prompt forbids new areas" do
    Shiplog.config.max_areas = 1
    Shiplog::Area.create!(name: "Billing")
    text = prompt

    assert_includes text, "Do not invent a new area"
    assert_not_includes text, "1–3 words"
  end

  test "without areas and with max_areas 0 the prompt does not mention areas" do
    Shiplog.config.max_areas = 0

    assert_not_includes prompt, %("area")
  end

  test "roadmap prompts ask for an area too" do
    Shiplog::Area.create!(name: "Imports")

    assert_includes prompt(shiplog_entries(:soon_item_roadmap)), "Imports"
  end
end
