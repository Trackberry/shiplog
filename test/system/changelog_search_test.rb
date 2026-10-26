require "application_system_test_case"

class ChangelogSearchTest < ApplicationSystemTestCase
  test "typing a query filters the changelog and clearing restores it" do
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 9, 15))
    visit "/changelog"
    assert_selector ".shiplog-entry", count: 2

    fill_in "Search the changelog", with: "csv"
    click_button "Search"

    assert_current_path "/changelog?q=csv"
    assert_selector ".shiplog-entry", count: 1
    assert_selector ".shiplog-entry__title", text: "Better CSV validation"
    assert_selector ".shiplog-search__summary", text: "1 result for “csv”"
    assert_field "Search the changelog", with: "csv"

    click_link "Clear search"
    assert_current_path "/changelog"
    assert_selector ".shiplog-entry", count: 2
    assert_no_selector ".shiplog-search__summary"
  end
end
