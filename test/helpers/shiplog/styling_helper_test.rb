require "test_helper"

class Shiplog::StylingHelperTest < ActionView::TestCase
  include Shiplog::StylingHelper

  test "returns the stable BEM class" do
    assert_equal "shiplog-card", shiplog_class(:card)
  end

  test "appends modifiers as BEM modifiers" do
    assert_equal "shiplog-entry shiplog-entry--feature", shiplog_class(:entry, :feature)
    assert_equal "shiplog-page shiplog-page--roadmap", shiplog_class(:page, "roadmap")
    assert_equal "shiplog-column shiplog-column--in-progress", shiplog_class(:column, "in_progress")
  end

  test "adds the configured classes after the BEM class" do
    Shiplog.config.classes = { card: "rounded border", entry: %w[p-4 bg-white] }
    assert_equal "shiplog-card rounded border", shiplog_class(:card)
    assert_equal "shiplog-entry shiplog-entry--change p-4 bg-white", shiplog_class(:entry, :change)
  end

  test "configured classes may use string keys" do
    Shiplog.config.classes = { "card" => "rounded" }
    assert_equal "shiplog-card rounded", shiplog_class(:card)
  end

  test "blank configured classes are ignored" do
    Shiplog.config.classes = { card: "  " }
    assert_equal "shiplog-card", shiplog_class(:card)
  end

  test "unknown keys raise and list the valid keys" do
    error = assert_raises(ArgumentError) { shiplog_class(:nope) }
    assert_match(/Unknown Shiplog class key :nope/, error.message)
    assert_includes error.message, Shiplog::Classes::KEYS.join(", ")
  end
end
