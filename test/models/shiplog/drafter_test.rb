require "test_helper"

class Shiplog::DrafterTest < ActiveJob::TestCase
  setup { travel_to Time.utc(2026, 10, 26, 12) }

  def roadmap_entries = Shiplog::Entry.roadmap

  test "creates a roadmap draft for every roadmap item without one and enqueues a rewrite" do
    item = shiplog_issues(:export_report)
    assert_nil item.entries.find_by(kind: "roadmap")

    assert_enqueued_with(job: Shiplog::RewriteEntryJob) { Shiplog::Drafter.call }

    entry = item.entries.find_by!(kind: "roadmap")
    assert entry.draft?
    assert_equal "Export report", entry.title
    assert_enqueued_with(job: Shiplog::RewriteEntryJob, args: [ entry.id ])
  end

  test "does not touch existing roadmap entries" do
    assert_no_difference -> { shiplog_issues(:bulk_upload).entries.count } do
      Shiplog::Drafter.call
    end
    assert shiplog_entries(:bulk_upload_roadmap).reload.approved?
  end

  test "is idempotent" do
    Shiplog::Drafter.call
    assert_no_difference -> { Shiplog::Entry.count } do
      assert_no_enqueued_jobs { Shiplog::Drafter.call }
    end
  end

  test "creates a feature draft for a completed issue with a merged PR on a descendant" do
    issue = shiplog_issues(:bulk_upload)
    issue.update!(state: "closed", state_reason: "completed", closed_at: Time.utc(2026, 10, 12))

    Shiplog::Drafter.call

    entry = issue.entries.find_by!(kind: "feature")
    assert entry.draft?
    assert_equal Date.new(2026, 10, 11), entry.released_on
  end

  test "released_on is the newest merged_at across the tree" do
    issue = shiplog_issues(:bulk_upload)
    issue.update!(state: "closed", state_reason: "completed", closed_at: Time.utc(2026, 10, 12))
    pr = Shiplog::PullRequest.create!(repository: issue.repository, node_id: "PR_late", number: 99, title: "Late", state: "merged",
      merged_at: Time.utc(2026, 10, 20, 8), labels: [], github_updated_at: Time.current)
    Shiplog::IssueLink.create!(issue_node_id: issue.node_id, pull_request_node_id: pr.node_id)

    Shiplog::Drafter.call

    assert_equal Date.new(2026, 10, 20), issue.entries.find_by!(kind: "feature").released_on
  end

  test "does not create a feature draft for issues closed more than 90 days ago" do
    issue = shiplog_issues(:bulk_upload)
    issue.update!(state: "closed", state_reason: "completed", closed_at: Time.utc(2026, 10, 26, 12) - 91.days)

    Shiplog::Drafter.call

    assert_not issue.entries.exists?(kind: "feature")
  end

  test "does not create a feature draft when closed as not planned" do
    issue = shiplog_issues(:bulk_upload)
    issue.update!(state: "closed", state_reason: "not_planned")

    Shiplog::Drafter.call

    assert_not issue.entries.exists?(kind: "feature")
  end

  test "does not create a feature draft without a merged PR" do
    issue = shiplog_issues(:export_report)
    issue.update!(state: "closed", state_reason: "completed", closed_at: Time.utc(2026, 10, 12))

    Shiplog::Drafter.call

    assert_not issue.entries.exists?(kind: "feature")
  end

  test "does not create a feature draft for a child of a public issue" do
    child = shiplog_issues(:bulk_upload_csv_validation)
    child.update!(state: "closed", state_reason: "completed", closed_at: Time.utc(2026, 10, 12))

    Shiplog::Drafter.call

    assert_not child.entries.exists?(kind: "feature")
  end

  test "survives a race on the unique index" do
    issue = shiplog_issues(:export_report)
    Shiplog::Entry.create!(subject: issue, kind: "roadmap")

    assert_nothing_raised { Shiplog::Drafter.draft(issue, "roadmap") }
    assert_equal 1, issue.entries.where(kind: "roadmap").count
  end

  test "reads do not grow with the number of new items" do
    Shiplog::Drafter.call
    baseline = selects { Shiplog::Drafter.call }
    5.times do |i|
      Shiplog::Issue.create!(repository: shiplog_repositories(:app), node_id: "I_extra_#{i}", number: 100 + i, title: "Extra #{i}",
        labels: [ "public" ], github_created_at: Time.current, github_updated_at: Time.current)
    end

    assert_equal baseline, selects { Shiplog::Drafter.call }
    assert_equal 5, Shiplog::Entry.roadmap.where(subject: Shiplog::Issue.where("node_id LIKE 'I_extra_%'")).count
  end

  private
    def selects
      count = 0
      callback = ->(*, payload) { count += 1 if payload[:sql].start_with?("SELECT") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      count
    end
end
