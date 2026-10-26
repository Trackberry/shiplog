require "application_system_test_case"

class BoardTest < ApplicationSystemTestCase
  test "dragging a card pins it and updates the card without a reload" do
    moved = shiplog_issues(:export_report)
    visit "/admin/shiplog/board"
    page.execute_script("window.shiplogNotReloaded = true")

    card = find(".shiplog-card[data-issue-id='#{moved.id}']")
    card.drag_to find("[data-column=later]")

    within "[data-column=later] .shiplog-card[data-issue-id='#{moved.id}']" do
      assert_selector ".shiplog-badge", text: I18n.t("shiplog.admin.board.pinned")
      assert_equal "later", find("select").value
      assert_button I18n.t("shiplog.admin.board.unpin")
    end
    assert page.evaluate_script("window.shiplogNotReloaded"), "the board was reloaded"
    assert_equal "later", moved.reload.pinned_column
  end
end
