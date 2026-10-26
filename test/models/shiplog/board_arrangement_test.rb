require "test_helper"

class Shiplog::BoardArrangementTest < ActiveSupport::TestCase
  def arrange(column, moved, ids)
    Shiplog::BoardArrangement.new(column:, moved_id: moved.id, issue_ids: ids.map(&:id)).save!
  end

  def natural_columns
    Shiplog::Roadmap.new(published_only: false).items.to_h { |item| [ item.issue.id, item.column ] }
  end

  test "save pins only the moved card and positions everyone in order" do
    moved = shiplog_issues(:export_report)
    bystander = shiplog_issues(:bulk_upload)
    before = natural_columns
    arrange("coming_soon", moved, [ moved, bystander ])
    assert_equal [ "coming_soon", 0 ], [ moved.reload.pinned_column, moved.position ]
    assert_nil bystander.reload.pinned_column
    assert_equal 1, bystander.position
    assert_equal before[bystander.id], natural_columns[bystander.id]
  end

  test "accepts string ids" do
    issue = shiplog_issues(:export_report)
    Shiplog::BoardArrangement.new(column: "later", moved_id: issue.id.to_s, issue_ids: [ issue.id.to_s ]).save!
    assert_equal "later", issue.reload.pinned_column
  end

  test "ids that are not roadmap items raise and change nothing" do
    good = shiplog_issues(:export_report)
    private_issue = shiplog_issues(:refactor_db)
    assert_raises(ActiveRecord::RecordNotFound) { arrange("later", good, [ good, private_issue ]) }
    assert_nil good.reload.pinned_column
    assert_nil good.position
  end

  test "a moved card that is not a roadmap item raises" do
    private_issue = shiplog_issues(:refactor_db)
    assert_raises(ActiveRecord::RecordNotFound) { arrange("later", private_issue, [ private_issue ]) }
    assert_nil private_issue.reload.pinned_column
  end

  test "moved_id must be included in issue_ids" do
    moved = shiplog_issues(:export_report)
    other = shiplog_issues(:bulk_upload)
    assert_raises(ArgumentError) { arrange("later", moved, [ other ]) }
    assert_nil moved.reload.pinned_column
    assert_nil other.reload.position
  end

  test "an invalid column raises ArgumentError" do
    issue = shiplog_issues(:export_report)
    assert_raises(ArgumentError) { arrange("nope", issue, [ issue ]) }
  end

  test "unpin! clears pinned_column and position" do
    issue = shiplog_issues(:pinned_item)
    issue.update!(position: 3)
    Shiplog::BoardArrangement.unpin!(issue)
    assert_equal [ nil, nil ], [ issue.reload.pinned_column, issue.position ]
  end
end
