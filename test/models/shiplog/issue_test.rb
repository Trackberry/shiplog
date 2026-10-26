require "test_helper"

class Shiplog::IssueTest < ActiveSupport::TestCase
  test "public? uses the configured label" do
    assert shiplog_issues(:bulk_upload).public?
    refute shiplog_issues(:refactor_db).public?
  end

  test "parent and children resolve by node_id across repositories" do
    parent = shiplog_issues(:bulk_upload)
    child = shiplog_issues(:bulk_upload_csv)
    assert_not_equal parent.repository, child.repository
    assert_equal parent, child.parent
    assert_includes parent.children, child
  end

  test "descendants walks nested sub-issues" do
    assert_includes shiplog_issues(:bulk_upload).descendants, shiplog_issues(:bulk_upload_csv_validation)
  end

  test "linked_pull_requests goes through issue_links by node_id" do
    assert_includes shiplog_issues(:bulk_upload_csv).linked_pull_requests, shiplog_pull_requests(:csv_import)
  end

  test "open scope and publicly_labeled scope" do
    assert_includes Shiplog::Issue.open, shiplog_issues(:bulk_upload)
    assert_not_includes Shiplog::Issue.open, shiplog_issues(:dark_mode)
    assert_includes Shiplog::Issue.publicly_labeled, shiplog_issues(:bulk_upload)
    assert_not_includes Shiplog::Issue.publicly_labeled, shiplog_issues(:refactor_db)
  end

  test "pinned_column only accepts known columns" do
    assert_equal "later", shiplog_issues(:pinned_item).pinned_column
    issue = shiplog_issues(:bulk_upload)
    issue.pinned_column = "nowhere"
    refute issue.valid?
  end
end
