require "test_helper"

class Shiplog::ClassesTest < ActiveSupport::TestCase
  EXPECTED_KEYS = %i[
    page page_header page_title page_lede
    columns column column_header column_title column_count column_description column_empty
    cards card card_title card_body
    months month month_title
    entries entry entry_feature entry_category entry_title entry_body entry_date
    pagination pagination_link empty
  ].freeze

  test "KEYS is the frozen public list" do
    assert_equal EXPECTED_KEYS, Shiplog::Classes::KEYS
    assert_predicate Shiplog::Classes::KEYS, :frozen?
  end

  test "every key has a stable BEM class" do
    assert_equal Shiplog::Classes::KEYS.sort, Shiplog::Classes::BEM.keys.sort
    assert_equal "shiplog-card", Shiplog::Classes::BEM[:card]
    assert_equal "shiplog-entry--feature", Shiplog::Classes::BEM[:entry_feature]
    assert_equal "shiplog-column__title", Shiplog::Classes::BEM[:column_title]
  end
end
