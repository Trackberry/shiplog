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

  test "cards do not link to non-GitHub urls" do
    shiplog_issues(:export_report).update!(url: "javascript:alert(1)")
    get "/admin/shiplog/board"
    assert_select "a[href^=javascript]", count: 0
    assert_select ".shiplog-card[data-issue-id=?]", shiplog_issues(:export_report).id.to_s, text: /Trackberry\/trackberry#5/
  end

  test "show does not issue more queries for more cards" do
    repository = shiplog_repositories(:ios)
    add_cards = lambda do |count, offset|
      count.times do |i|
        n = 2000 + offset + i
        Shiplog::Issue.create!(repository:, node_id: "I_b#{n}", number: n, title: "Card #{n}", labels: [ "public" ],
          url: "https://github.com/x/y/issues/#{n}", github_updated_at: Time.current)
      end
    end
    add_cards.call(2, 0)
    few = count_queries { get "/admin/shiplog/board" }
    add_cards.call(4, 10)
    many = count_queries { get "/admin/shiplog/board" }
    assert_select ".shiplog-card", minimum: 6
    assert_equal few, many, "few=#{few} many=#{many}"
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

  def patch_json(params)
    patch "/admin/shiplog/board", params:, as: :json
  end

  test "json update pins only the moved card, orders the column and returns 204" do
    moved = shiplog_issues(:export_report)
    bystander = shiplog_issues(:later_item)
    natural = Shiplog::Roadmap.new(published_only: false).items.to_h { |item| [ item.issue.id, item.column ] }
    patch_json column: "coming_soon", moved_id: moved.id, issue_ids: [ bystander.id, moved.id ]
    assert_response :no_content
    assert_equal [ "coming_soon", 1 ], [ moved.reload.pinned_column, moved.position ]
    assert_nil bystander.reload.pinned_column
    assert_equal 0, bystander.position
    assert_equal natural[bystander.id], Shiplog::Roadmap.new(published_only: false).items.find { |item| item.issue.id == bystander.id }.column
  end

  test "json update with a bad column is 422" do
    id = shiplog_issues(:export_report).id
    patch_json column: "nope", moved_id: id, issue_ids: [ id ]
    assert_response :unprocessable_content
    assert_equal "application/json", response.media_type
  end

  test "json update with foreign ids is 422 and changes nothing" do
    good = shiplog_issues(:export_report)
    foreign = shiplog_issues(:refactor_db)
    patch_json column: "later", moved_id: good.id, issue_ids: [ good.id, foreign.id ]
    assert_response :unprocessable_content
    assert_nil good.reload.pinned_column
    assert_nil foreign.reload.pinned_column
  end

  test "json update whose moved_id is foreign is 422" do
    foreign = shiplog_issues(:refactor_db)
    patch_json column: "later", moved_id: foreign.id, issue_ids: [ foreign.id ]
    assert_response :unprocessable_content
  end

  test "json update whose issue_ids omit moved_id is 422" do
    moved = shiplog_issues(:export_report)
    other = shiplog_issues(:later_item)
    patch_json column: "later", moved_id: moved.id, issue_ids: [ other.id ]
    assert_response :unprocessable_content
    assert_nil moved.reload.pinned_column
    assert_nil other.reload.position
  end

  test "json update with a garbage id is 422" do
    patch_json column: "later", moved_id: "abc", issue_ids: [ "abc" ]
    assert_response :unprocessable_content
  end

  test "json update without ids is 422" do
    patch_json column: "later", moved_id: shiplog_issues(:export_report).id
    assert_response :unprocessable_content
  end

  test "form fallback pins only the moved card at the end of the column" do
    mover = shiplog_issues(:export_report)
    bystanders = Shiplog::Roadmap.new(published_only: false).columns["later"].map(&:issue).reject { |issue| issue.id == mover.id }
    pinned_before = bystanders.to_h { |issue| [ issue.id, issue.pinned_column ] }
    patch "/admin/shiplog/board", params: { issue_id: mover.id, column: "later" }
    assert_redirected_to "/admin/shiplog/board"
    assert_equal "later", mover.reload.pinned_column
    assert_equal pinned_before, bystanders.to_h { |issue| [ issue.id, issue.reload.pinned_column ] }
    later = Shiplog::Roadmap.new(published_only: false).columns["later"].map { |item| item.issue.id }
    assert_equal mover.id, later.last
  end

  test "form fallback leaves other cards unpinned even when the column has positions" do
    mover = shiplog_issues(:export_report)
    other = shiplog_issues(:later_item)
    other.update!(position: 7)
    column = Shiplog::Roadmap.new(published_only: false).items.find { |item| item.issue.id == other.id }.column
    patch "/admin/shiplog/board", params: { issue_id: mover.id, column: }
    assert_equal column, mover.reload.pinned_column
    assert_nil other.reload.pinned_column
    ids = Shiplog::Roadmap.new(published_only: false).columns[column].map { |item| item.issue.id }
    assert_equal mover.id, ids.last
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
    patch "/admin/shiplog/board", params: { column: "later", moved_id: 1, issue_ids: [ 1 ] }, as: :json
    assert_response :forbidden
  end
end
