require "test_helper"

class Shiplog::Sync::PullRequestImporterTest < ActiveSupport::TestCase
  setup do
    @repository = Shiplog::Repository.create!(full_name: "Acme/widgets")
    @nodes = JSON.parse(github_fixture("pull_requests")).dig("data", "repository", "pullRequests", "nodes")
    @importer = Shiplog::Sync::PullRequestImporter.new(@repository)
  end

  test "maps states and fields" do
    merged = @importer.import(@nodes[0])
    open_pr = @importer.import(@nodes[1])
    closed = @importer.import(@nodes[2])

    assert_equal %w[merged open closed], [ merged, open_pr, closed ].map(&:state)
    assert_equal "octocat", merged.author_login
    assert_equal %w[feature], merged.labels
    assert_equal Time.utc(2026, 10, 20, 10), merged.merged_at
  end

  test "replaces links from closingIssuesReferences" do
    pull_request = @importer.import(@nodes[0])
    assert_equal %w[I_kwDOSync001], Shiplog::IssueLink.where(pull_request_node_id: pull_request.node_id).pluck(:issue_node_id)

    changed = @nodes[0].deep_dup
    changed["updatedAt"] = "2026-10-21T10:00:00Z"
    changed["closingIssuesReferences"]["nodes"] = [ { "id" => "I_kwDOSync002" } ]
    @importer.import(changed)

    assert_equal %w[I_kwDOSync002], Shiplog::IssueLink.where(pull_request_node_id: pull_request.node_id).pluck(:issue_node_id)
  end

  test "leaves links alone when the node has no closingIssuesReferences" do
    Shiplog::IssueLink.create!(issue_node_id: "I_x", pull_request_node_id: "PR_kwDOSync103")
    node = @nodes[0].except("closingIssuesReferences")

    @importer.import(node)

    assert Shiplog::IssueLink.exists?(issue_node_id: "I_x", pull_request_node_id: "PR_kwDOSync103")
  end
end
