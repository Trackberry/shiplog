require "application_system_test_case"

class InboxTest < ApplicationSystemTestCase
  test "approving on the drafts list removes the row without a reload" do
    entry = shiplog_entries(:csv_change_draft)
    visit "/admin/shiplog/?status=draft"
    page.execute_script("window.shiplogNotReloaded = true")

    within("#shiplog-entry-#{entry.id}") { click_button I18n.t("shiplog.admin.entries.approve") }

    assert_no_selector "#shiplog-entry-#{entry.id}"
    assert_selector "[data-shiplog-inbox] [role=status]", text: I18n.t("shiplog.admin.entries.approved")
    assert_selector "[data-shiplog-inbox] [role=status]", text: entry.title
    assert page.evaluate_script("window.shiplogNotReloaded"), "the inbox was reloaded"
    assert_equal "approved", entry.reload.status
  end

  test "a row that still matches the filter is replaced rather than removed" do
    entry = shiplog_entries(:csv_change_draft)
    visit "/admin/shiplog/?status=draft&kind=change"
    page.execute_script("window.shiplogNotReloaded = true")
    # Approve is only offered on draft rows, so point the form at an approved-list filter to see the
    # response for an entry that stays in the list.
    page.execute_script(<<~JS)
      const form = document.querySelector("#shiplog-entry-#{entry.id} form[data-shiplog-inline]")
      form.action = form.action.replace("status=draft", "status=approved")
    JS

    within("#shiplog-entry-#{entry.id}") { click_button I18n.t("shiplog.admin.entries.approve") }

    assert_selector "#shiplog-entry-#{entry.id}", text: entry.title
    assert_no_button I18n.t("shiplog.admin.entries.approve")
    assert_selector "[role=status]", text: I18n.t("shiplog.admin.entries.approved")
    assert page.evaluate_script("window.shiplogNotReloaded")
  end

  test "restoring on the discarded list removes the row" do
    entry = shiplog_entries(:typo_change_discarded)
    visit "/admin/shiplog/?status=discarded"
    page.execute_script("window.shiplogNotReloaded = true")

    within("#shiplog-entry-#{entry.id}") { click_button I18n.t("shiplog.admin.entries.restore") }

    assert_no_selector "#shiplog-entry-#{entry.id}"
    assert_selector "[role=status]", text: I18n.t("shiplog.admin.entries.restored")
    assert_text I18n.t("shiplog.admin.entries.empty")
    assert page.evaluate_script("window.shiplogNotReloaded")
    assert_equal "draft", entry.reload.status
  end
end
