require "test_helper"

class Shiplog::Admin::BoardsControllerTest < ActionDispatch::IntegrationTest
  test "show lists items in columns including unapproved ones" do
    get "/admin/shiplog/board"
    assert_response :ok
    assert_select "[data-column=in_progress]"
    assert_select "[data-column=coming_soon]"
    assert_select "[data-column=later]"
    assert_select "[data-board-url=?]", "/admin/shiplog/board"
    assert_select "[data-column=coming_soon] .shiplog-card[data-issue-id=?]", shiplog_issues(:soon_item).id.to_s
  end

  test "cards show entry title, falling back to the issue title, with badges" do
    get "/admin/shiplog/board"
    assert_select ".shiplog-card[data-issue-id=?] .shiplog-card__title", shiplog_issues(:bulk_upload).id.to_s, text: "Upload many shipments at once"
    assert_select ".shiplog-card[data-issue-id=?] .shiplog-card__title", shiplog_issues(:export_report).id.to_s, text: "Export report"
    assert_select ".shiplog-card[data-issue-id=?] .shiplog-badge", shiplog_issues(:export_report).id.to_s, text: "Not approved"
    assert_select ".shiplog-card[data-issue-id=?] .shiplog-badge", shiplog_issues(:soon_item).id.to_s, text: "Not approved"
    assert_select ".shiplog-card[data-issue-id=?] .shiplog-badge", shiplog_issues(:bulk_upload).id.to_s, text: "Not approved", count: 0
    assert_select ".shiplog-card[data-issue-id=?] .shiplog-badge", shiplog_issues(:pinned_item).id.to_s, text: "Pinned"
  end

  test "cards link to GitHub and escape titles" do
    shiplog_issues(:export_report).update!(title: "<img src=x>")
    get "/admin/shiplog/board"
    assert_select "a[href=?]", "https://github.com/Trackberry/trackberry/issues/5", text: "Trackberry/trackberry#5"
    assert_not_includes response.body, "<img src=x>"
  end

  test "each card has a fallback move form and pinned cards an unpin button" do
    get "/admin/shiplog/board"
    id = shiplog_issues(:export_report).id
    assert_select ".shiplog-card[data-issue-id=?] form[action=?]", id.to_s, "/admin/shiplog/board" do
      assert_select "select[name=column] option", 3
      assert_select "input[name=issue_id][value=?]", id.to_s
    end
    assert_select ".shiplog-card[data-issue-id=?] input[name=unpin]", id.to_s, count: 0
    assert_select ".shiplog-card[data-issue-id=?] input[name=unpin]", shiplog_issues(:pinned_item).id.to_s
  end

  test "board loads the board script" do
    get "/admin/shiplog/board"
    assert_select "script[type=module][src=?]", "/admin/shiplog/assets/#{Shiplog::VERSION}/board.js"
  end

  test "json update pins and orders and returns 204" do
    a = shiplog_issues(:export_report)
    b = shiplog_issues(:later_item)
    patch "/admin/shiplog/board", params: { column: "coming_soon", issue_ids: [ b.id, a.id ] }, as: :json
    assert_response :no_content
    assert_equal [ "coming_soon", 0 ], [ b.reload.pinned_column, b.position ]
    assert_equal [ "coming_soon", 1 ], [ a.reload.pinned_column, a.position ]
  end

  test "json update with a bad column is 422" do
    patch "/admin/shiplog/board", params: { column: "nope", issue_ids: [ shiplog_issues(:export_report).id ] }, as: :json
    assert_response :unprocessable_content
    assert_equal "application/json", response.media_type
  end

  test "json update with unknown ids is 422" do
    patch "/admin/shiplog/board", params: { column: "later", issue_ids: [ shiplog_issues(:refactor_db).id ] }, as: :json
    assert_response :unprocessable_content
    assert_nil shiplog_issues(:refactor_db).reload.pinned_column
  end

  test "json update without ids is 422" do
    patch "/admin/shiplog/board", params: { column: "later" }, as: :json
    assert_response :unprocessable_content
  end

  test "form fallback appends to the end of the column" do
    mover = shiplog_issues(:export_report)
    patch "/admin/shiplog/board", params: { issue_id: mover.id, column: "later" }
    assert_redirected_to "/admin/shiplog/board"
    mover.reload
    assert_equal "later", mover.pinned_column
    later_ids = Shiplog::Roadmap.new(published_only: false).columns["later"].map { |issue| issue.issue.id }
    assert_equal mover.id, later_ids.last
  end

  test "form fallback with a bad column redirects with an alert" do
    patch "/admin/shiplog/board", params: { issue_id: shiplog_issues(:export_report).id, column: "nope" }
    assert_redirected_to "/admin/shiplog/board"
    assert flash[:alert].present?
  end

  test "unpin clears the pin" do
    issue = shiplog_issues(:pinned_item)
    patch "/admin/shiplog/board", params: { issue_id: issue.id, unpin: "1" }
    assert_redirected_to "/admin/shiplog/board"
    assert_nil issue.reload.pinned_column
  end
end

class Shiplog::Admin::BoardAuthorizationTest < ActionDispatch::IntegrationTest
  test "board is forbidden when authorize_admin returns false" do
    Shiplog.config.authorize_admin = ->(_controller) { false }
    get "/admin/shiplog/board"
    assert_response :forbidden
    patch "/admin/shiplog/board", params: { column: "later", issue_ids: [ 1 ] }, as: :json
    assert_response :forbidden
  end
end
