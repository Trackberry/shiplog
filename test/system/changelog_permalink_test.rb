require "application_system_test_case"

class ChangelogPermalinkTest < ApplicationSystemTestCase
  test "clicking a title on the changelog lands on its permalink, and back returns to the month" do
    visit "/changelog"
    click_link "Dark mode"

    assert_current_path "/changelog/dark-mode"
    assert_selector "article.shiplog-permalink .shiplog-entry__title", text: "Dark mode"
    assert_selector ".shiplog-entry__body", text: "Switch to a dark theme."

    click_link "Back to the changelog"
    assert_current_path "/changelog"
    assert_equal "shiplog-month-2026-10", URI(current_url).fragment
    assert_selector "h2.shiplog-month__title", text: "October 2026"
  end
end
