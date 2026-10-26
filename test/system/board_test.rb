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

  test "the board keeps working after a Turbo-style page swap" do
    moved = shiplog_issues(:export_report)
    visit "/admin/shiplog/board"
    page.execute_script(<<~JS)
      window.shiplogNotReloaded = true
      const board = document.querySelector("[data-board-url]")
      const fresh = board.cloneNode(true)
      fresh.removeAttribute("data-shiplog-bound") // as parsed from server HTML, not copied from the old element
      board.replaceWith(fresh)
      document.dispatchEvent(new Event("turbo:load"))
    JS

    find(".shiplog-card[data-issue-id='#{moved.id}']").drag_to find("[data-column=later]")

    assert_selector "[data-column=later] .shiplog-card[data-issue-id='#{moved.id}'] .shiplog-badge", text: I18n.t("shiplog.admin.board.pinned")
    assert page.evaluate_script("window.shiplogNotReloaded"), "the board was reloaded"
  end
end
