require "test_helper"

class Shiplog::RoadmapTest < ActiveSupport::TestCase
  def items = Shiplog::Roadmap.new(published_only: false).items
  def issues = items.map(&:issue)
  def column_of(name) = Shiplog::Roadmap::ColumnResolver.new(shiplog_issues(name)).column

  test "a public open top-level issue is an item" do
    assert_includes issues, shiplog_issues(:bulk_upload)
  end

  test "a closed issue is not an item" do
    assert_not_includes issues, shiplog_issues(:dark_mode)
  end

  test "a non-public issue is not an item" do
    assert_not_includes issues, shiplog_issues(:refactor_db)
  end

  test "a public child of a public parent is folded into it" do
    assert_not_includes issues, shiplog_issues(:bulk_upload_csv)
    assert_not_includes issues, shiplog_issues(:bulk_upload_csv_validation)
  end

  test "a public child of a non-public parent is an item" do
    assert_includes issues, shiplog_issues(:public_child_of_private)
  end

  test "in_progress when the issue has an open linked PR" do
    assert_equal "in_progress", column_of(:export_report)
  end

  test "in_progress when a descendant has an open linked PR" do
    assert_equal "in_progress", column_of(:bulk_upload)
  end

  test "a merged linked PR alone does not make an issue in_progress" do
    shiplog_pull_requests(:csv_import).update!(state: "merged")
    assert_equal "later", column_of(:bulk_upload)
  end

  test "in_progress when assignees_count is positive" do
    assert_equal "in_progress", column_of(:assigned_task)
  end

  test "coming_soon with a milestone" do
    assert_equal "coming_soon", column_of(:milestone_item)
  end

  test "coming_soon with a soon label" do
    assert_equal "coming_soon", column_of(:soon_item)
  end

  test "later otherwise" do
    assert_equal "later", column_of(:later_item)
  end

  test "pinned_column overrides everything" do
    assert shiplog_issues(:pinned_item).assignees_count.positive?
    assert_equal "later", column_of(:pinned_item)
  end

  test "columns returns the three columns in order, even when empty" do
    columns = Shiplog::Roadmap.new(published_only: false).columns
    assert_equal %w[in_progress coming_soon later], columns.keys
    assert_includes columns["coming_soon"].map(&:issue), shiplog_issues(:milestone_item)
  end

  test "published_only only includes items whose roadmap entry is approved" do
    published = Shiplog::Roadmap.new(published_only: true).items.map(&:issue)
    assert_equal [ shiplog_issues(:bulk_upload), shiplog_issues(:later_item) ].sort_by(&:id), published.sort_by(&:id)
    assert_not_includes published, shiplog_issues(:soon_item)
  end

  test "items carry their entry, including unapproved drafts when not published_only" do
    item = items.find { |i| i.issue == shiplog_issues(:soon_item) }
    assert item.entry.draft?
    assert_nil items.find { |i| i.issue == shiplog_issues(:milestone_item) }.entry
  end

  test "ordering is position ascending nulls last, then github_updated_at descending" do
    shiplog_issues(:bulk_upload).update!(position: 1)
    in_progress = Shiplog::Roadmap.new(published_only: false).columns["in_progress"].map(&:issue)
    assert_equal [ :bulk_upload, :assigned_task, :export_report ].map { |n| shiplog_issues(n) }, in_progress
  end

  test "ordering sorts two non-null positions ascending" do
    shiplog_issues(:export_report).update!(position: 1)
    shiplog_issues(:assigned_task).update!(position: 2)
    shiplog_issues(:bulk_upload).update!(position: 3)
    in_progress = Shiplog::Roadmap.new(published_only: false).columns["in_progress"].map(&:issue)
    assert_equal [ :export_report, :assigned_task, :bulk_upload ].map { |n| shiplog_issues(n) }, in_progress
  end

  test "published_only restricts columns too" do
    columns = Shiplog::Roadmap.new(published_only: true).columns
    assert_equal [ shiplog_issues(:bulk_upload) ], columns["in_progress"].map(&:issue)
    assert_equal [ shiplog_issues(:later_item) ], columns["later"].map(&:issue)
    assert_empty columns["coming_soon"]
  end

  test "query count does not grow with the number of items" do
    small = count_queries { Shiplog::Roadmap.new(published_only: false).columns }
    4.times { |i| create_tree(i) }
    large = count_queries { Shiplog::Roadmap.new(published_only: false).columns }
    assert_equal small, large
  end

  private
    def create_tree(i)
      repo = shiplog_repositories(:app)
      attrs = { repository: repo, state: "open", labels: [ "public" ], assignees_count: 0,
                url: "https://example.com/#{i}", github_created_at: Time.current, github_updated_at: Time.current }
      root = Shiplog::Issue.create!(attrs.merge(node_id: "I_n#{i}", number: 100 + i * 3, title: "Root #{i}", body: ""))
      mid = Shiplog::Issue.create!(attrs.merge(node_id: "I_n#{i}_c", number: 101 + i * 3, title: "Mid #{i}", body: "", parent_node_id: root.node_id))
      leaf = Shiplog::Issue.create!(attrs.merge(node_id: "I_n#{i}_l", number: 102 + i * 3, title: "Leaf #{i}", body: "", parent_node_id: mid.node_id))
      pr = Shiplog::PullRequest.create!(repository: repo, node_id: "PR_n#{i}", number: 200 + i, title: "PR", state: "open",
        author_login: "x", labels: [], url: "https://example.com/pr/#{i}", github_updated_at: Time.current)
      Shiplog::IssueLink.create!(issue_node_id: leaf.node_id, pull_request_node_id: pr.node_id)
    end

    def count_queries
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end
end
