require "test_helper"

class Shiplog::ClassesTest < ActiveSupport::TestCase
  EXPECTED_KEYS = %i[
    page page_header page_title page_lede
    switcher switcher_link
    columns column column_header column_marker column_title column_count column_description column_empty
    cards card card_title card_body card_meta card_tag
    shipped shipped_title shipped_list shipped_item shipped_date shipped_link
    footnote footnote_link
    months month month_title
    entries entry entry_feature entry_category entry_title entry_body entry_date
    pagination pagination_link empty
    search search_input search_button search_summary search_clear search_empty
    permalink permalink_back permalink_nav permalink_nav_link
    areas area_link entry_area
    entry_images entry_image
    announcement announcement_title announcement_body month_announcement month_announcement_link
    newsletter newsletter_title newsletter_hint newsletter_form newsletter_label newsletter_input newsletter_button newsletter_notice
  ].freeze

  test "KEYS is the frozen public list" do
    assert_equal EXPECTED_KEYS, Shiplog::Classes::KEYS
    assert_predicate Shiplog::Classes::KEYS, :frozen?
  end

  test "the permalink keys have BEM classes" do
    assert_equal "shiplog-permalink", Shiplog::Classes::BEM[:permalink]
    assert_equal "shiplog-permalink__back", Shiplog::Classes::BEM[:permalink_back]
    assert_equal "shiplog-permalink__nav", Shiplog::Classes::BEM[:permalink_nav]
    assert_equal "shiplog-permalink__nav-link", Shiplog::Classes::BEM[:permalink_nav_link]
  end

  test "the area keys have BEM classes" do
    assert_equal "shiplog-areas", Shiplog::Classes::BEM[:areas]
    assert_equal "shiplog-areas__link", Shiplog::Classes::BEM[:area_link]
    assert_equal "shiplog-entry__area", Shiplog::Classes::BEM[:entry_area]
  end

  test "every key has a stable BEM class" do
    assert_equal Shiplog::Classes::KEYS.sort, Shiplog::Classes::BEM.keys.sort
    assert_equal "shiplog-card", Shiplog::Classes::BEM[:card]
    assert_equal "shiplog-entry--feature", Shiplog::Classes::BEM[:entry_feature]
    assert_equal "shiplog-column__title", Shiplog::Classes::BEM[:column_title]
    assert_equal "shiplog-switcher__link", Shiplog::Classes::BEM[:switcher_link]
    assert_equal "shiplog-column__marker", Shiplog::Classes::BEM[:column_marker]
    assert_equal "shiplog-shipped__link", Shiplog::Classes::BEM[:shipped_link]
  end
end
