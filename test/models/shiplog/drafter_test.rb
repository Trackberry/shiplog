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
    Shiplog::Entry.update_all(rewritten_at: Time.current)
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

  test "does not draft a feature again after its entry was switched to a change" do
    issue = shiplog_issues(:bulk_upload)
    issue.update!(state: "closed", state_reason: "completed", closed_at: Time.utc(2026, 10, 12))
    Shiplog::Drafter.call
    issue.entries.find_by!(kind: "feature").update!(changelog_kind: "change")

    assert_no_difference -> { Shiplog::Entry.count } do
      Shiplog::Drafter.call
    end
    assert_equal [ "change" ], issue.entries.where(kind: %w[feature change]).pluck(:kind)
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

  test "no feature draft for a deleted issue" do
    issue = shiplog_issues(:bulk_upload)
    issue.update!(state: "closed", state_reason: "deleted", closed_at: Time.utc(2026, 10, 12))

    Shiplog::Drafter.call

    assert_not issue.entries.exists?(kind: "feature")
  end

  test "re-enqueues rewrites for drafts that were never rewritten and are over an hour old" do
    lost = shiplog_entries(:csv_change_draft)
    lost.update_columns(rewritten_at: nil, rewrite_error: nil, created_at: 2.hours.ago)

    assert_enqueued_with(job: Shiplog::RewriteEntryJob, args: [ lost.id ]) { Shiplog::Drafter.call }
  end

  test "does not re-enqueue recent, errored, rewritten or approved entries" do
    Shiplog::Entry.update_all(rewritten_at: Time.current)
    recent = shiplog_entries(:csv_change_draft)
    recent.update_columns(rewritten_at: nil, rewrite_error: nil, created_at: 10.minutes.ago)
    soon = shiplog_entries(:soon_item_roadmap)
    soon.update_columns(rewritten_at: nil, rewrite_error: "boom", created_at: 2.hours.ago)
    approved = shiplog_entries(:bulk_upload_roadmap)
    approved.update_columns(rewritten_at: nil, rewrite_error: nil, created_at: 2.hours.ago)

    Shiplog::Drafter.call

    ids = enqueued_jobs.select { |j| j["job_class"] == "Shiplog::RewriteEntryJob" }.flat_map { |j| j["arguments"] }
    assert_not_includes ids, recent.id
    assert_not_includes ids, soon.id
    assert_not_includes ids, approved.id
  end

  test "re-enqueues at most 100 lost rewrites per call" do
    Shiplog::Entry.update_all(rewritten_at: Time.current)
    repository = shiplog_repositories(:app)
    105.times do |i|
      issue = repository.issues.create!(node_id: "I_lost#{i}", number: 1000 + i, title: "t", body: "b", state: "open", labels: [],
        assignees_count: 0, url: "https://example.test/#{i}", github_created_at: 1.day.ago, github_updated_at: 1.day.ago)
      issue.entries.create!(kind: "change", title: "t", body: "b", created_at: 2.hours.ago)
    end

    lost_ids = Shiplog::Entry.where(rewritten_at: nil, kind: "change").ids
    Shiplog::Drafter.call

    requeued = enqueued_jobs.select { |j| j["job_class"] == "Shiplog::RewriteEntryJob" }.flat_map { |j| j["arguments"] } & lost_ids
    assert_equal 100, requeued.size
  end

  test "a new draft has its screenshots fetched once, whatever the number of rewrites" do
    Shiplog.config.github_token = "tok"
    Shiplog.config.rewriter = ->(_prompt) { '{"title":"T","body":"B","customer_facing":true}' }
    url = "https://user-images.githubusercontent.com/1/a.png"
    graphql = stub_request(:post, "https://api.github.com/graphql").to_return(body: { data: { node: { bodyHTML: %(<img src="#{url}">) } } }.to_json)
    stub_request(:get, url).to_return(body: image_bytes(:png))

    entry = Shiplog::Drafter.draft(shiplog_pull_requests(:dark_mode_pr), "feature")
    perform_enqueued_jobs
    Shiplog::RewriteEntryJob.perform_now(entry.id)
    Shiplog::RewriteEntryJob.perform_now(entry.id)

    assert_equal 1, entry.reload.ordered_images.size
    assert_requested graphql, times: 1
  end
end
