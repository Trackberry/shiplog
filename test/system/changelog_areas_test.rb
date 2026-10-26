require "application_system_test_case"

class ChangelogAreasTest < ApplicationSystemTestCase
  test "clicking an area on the changelog shows only its entries" do
    billing = Shiplog::Area.create!(name: "Billing")
    reports = Shiplog::Area.create!(name: "Reports")
    shiplog_entries(:dark_mode_feature).update!(area: billing)
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 9, 15), area: reports)

    visit "/changelog"
    assert_selector ".shiplog-entry__title", text: "Dark mode"
    assert_selector ".shiplog-entry__title", text: "Better CSV validation"

    click_link "Reports"

    assert_current_path "/changelog?area=reports"
    assert_selector ".shiplog-entry__title", text: "Better CSV validation"
    assert_no_selector ".shiplog-entry__title", text: "Dark mode"
    assert_selector "a.shiplog-areas__link--current", text: "Reports"

    click_link "All"
    assert_selector ".shiplog-entry__title", text: "Dark mode"
  end
end
