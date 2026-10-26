require "test_helper"

class Shiplog::Sync::IssueImporterTest < ActiveSupport::TestCase
  setup do
    @repository = Shiplog::Repository.create!(full_name: "Acme/widgets")
    @nodes = JSON.parse(github_fixture("issues_page_1")).dig("data", "repository", "issues", "nodes")
    @importer = Shiplog::Sync::IssueImporter.new(@repository)
  end

  test "upserts by node_id and maps fields" do
    issue = @importer.import(@nodes[0])

    assert_equal "I_kwDOSync001", issue.node_id
    assert_equal %w[public soon], issue.labels
    assert_equal "v2", issue.milestone_title
    assert_equal 1, issue.assignees_count
    assert_equal "open", issue.state
    assert_nil issue.state_reason
    assert_no_difference -> { Shiplog::Issue.count } do
      @importer.import(@nodes[0])
    end
  end

  test "maps parent id, downcases state and state reason" do
    issue = @importer.import(@nodes[1])

    assert_equal "I_kwDOSync001", issue.parent_node_id
    assert_equal "closed", issue.state
    assert_equal "completed", issue.state_reason
    assert_equal Time.utc(2026, 10, 2, 10), issue.closed_at
  end

  test "upserts nested PRs, creating repositories by nameWithOwner" do
    @importer.import(@nodes[1])

    merged = Shiplog::PullRequest.find_by!(node_id: "PR_kwDOSync101")
    assert_equal "merged", merged.state
    assert_equal "Acme/widgets", merged.repository.full_name
    open_pr = Shiplog::PullRequest.find_by!(node_id: "PR_kwDOSync102")
    assert_equal "open", open_pr.state
    assert_equal "Acme/widgets-ios", open_pr.repository.full_name
  end

  test "replaces links so removed ones disappear" do
    issue = @importer.import(@nodes[1])
    assert_equal %w[PR_kwDOSync101 PR_kwDOSync102], issue.issue_links.pluck(:pull_request_node_id).sort

    changed = @nodes[1].deep_dup
    changed["updatedAt"] = "2026-10-04T10:00:00Z"
    changed["closedByPullRequestsReferences"]["nodes"].pop
    @importer.import(changed)

    assert_equal %w[PR_kwDOSync101], issue.issue_links.reload.pluck(:pull_request_node_id)
  end

  test "does not overwrite with an older updatedAt" do
    @importer.import(@nodes[0])
    older = @nodes[0].merge("title" => "Stale title", "updatedAt" => "2026-09-30T10:00:00Z")

    @importer.import(older)

    assert_equal "Issue 1 title", Shiplog::Issue.find_by!(node_id: "I_kwDOSync001").title
  end
end
