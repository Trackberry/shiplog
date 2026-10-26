require "test_helper"

class Shiplog::BoardArrangementTest < ActiveSupport::TestCase
  test "save pins both issues and positions them in order" do
    first = shiplog_issues(:export_report)
    second = shiplog_issues(:bulk_upload)
    Shiplog::BoardArrangement.new(column: "coming_soon", issue_ids: [ second.id, first.id ]).save!
    assert_equal [ "coming_soon", 0 ], [ second.reload.pinned_column, second.position ]
    assert_equal [ "coming_soon", 1 ], [ first.reload.pinned_column, first.position ]
  end

  test "accepts string ids" do
    issue = shiplog_issues(:export_report)
    Shiplog::BoardArrangement.new(column: "later", issue_ids: [ issue.id.to_s ]).save!
    assert_equal "later", issue.reload.pinned_column
  end

  test "ids that are not roadmap items raise and change nothing" do
    good = shiplog_issues(:export_report)
    private_issue = shiplog_issues(:refactor_db)
    assert_raises(ActiveRecord::RecordNotFound) do
      Shiplog::BoardArrangement.new(column: "later", issue_ids: [ good.id, private_issue.id ]).save!
    end
    assert_nil good.reload.pinned_column
  end

  test "an invalid column raises ArgumentError" do
    assert_raises(ArgumentError) do
      Shiplog::BoardArrangement.new(column: "nope", issue_ids: [ shiplog_issues(:export_report).id ]).save!
    end
  end

  test "unpin! clears pinned_column and position" do
    issue = shiplog_issues(:pinned_item)
    issue.update!(position: 3)
    Shiplog::BoardArrangement.unpin!(issue)
    assert_equal [ nil, nil ], [ issue.reload.pinned_column, issue.position ]
  end
end
