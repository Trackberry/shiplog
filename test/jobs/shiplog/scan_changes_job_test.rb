require "test_helper"

class Shiplog::ScanChangesJobTest < ActiveJob::TestCase
  GRAPHQL = "https://api.github.com/graphql".freeze

  setup do
    Shiplog.config.github_token = "tok"
    Shiplog.config.repositories = [ "Acme/widgets" ]
    @stub = stub_request(:post, GRAPHQL).to_return(body: github_fixture("commits"))
    travel_to Time.utc(2026, 10, 26, 12)
  end

  test "scans from seven days ago when never scanned and advances the window" do
    Shiplog::ScanChangesJob.perform_now

    repository = Shiplog::Repository.find_by!(full_name: "Acme/widgets")
    assert_equal Time.utc(2026, 10, 26, 12), repository.changes_scanned_at
    assert_requested(:post, GRAPHQL) { |req| JSON.parse(req.body).dig("variables", "since") == "2026-10-19T12:00:00Z" }
  end

  test "scans from changes_scanned_at" do
    Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 10))

    Shiplog::ScanChangesJob.perform_now

    assert_requested(:post, GRAPHQL) { |req| JSON.parse(req.body).dig("variables", "since") == "2026-10-10T00:00:00Z" }
  end

  test "drafts change entries for candidates and enqueues rewrites" do
    repository = Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 1))
    pr = repository.pull_requests.create!(node_id: "PR_x", number: 5, title: "Add thing", state: "merged", merged_at: Time.utc(2026, 10, 15, 9),
      author_login: "ed", labels: [], github_updated_at: Time.utc(2026, 10, 15))

    assert_enqueued_jobs 2, only: Shiplog::RewriteEntryJob do
      Shiplog::ScanChangesJob.perform_now
    end

    pr_entry = pr.entries.find_by!(kind: "change")
    assert pr_entry.draft?
    assert_equal Date.new(2026, 10, 15), pr_entry.released_on
    commit = repository.commits.find_by!(sha: "a" * 40)
    assert_equal Date.new(2026, 10, 12), commit.entries.find_by!(kind: "change").released_on
    assert_not repository.commits.find_by!(sha: "c" * 40).entries.exists?
  end

  test "is idempotent" do
    Shiplog::Repository.create!(full_name: "Acme/widgets", changes_scanned_at: Time.utc(2026, 10, 1))
    Shiplog::ScanChangesJob.perform_now

    assert_no_difference -> { Shiplog::Entry.count } do
      Shiplog::Repository.update_all(changes_scanned_at: Time.utc(2026, 10, 1))
      Shiplog::ScanChangesJob.perform_now
    end
  end

  test "advances the window even with no candidates" do
    stub_request(:post, GRAPHQL).to_return(body: { data: { repository: { defaultBranchRef: nil } } }.to_json)


    assert_no_difference -> { Shiplog::Entry.count } do
      Shiplog::ScanChangesJob.perform_now
    end

    assert_equal Time.utc(2026, 10, 26, 12), Shiplog::Repository.find_by!(full_name: "Acme/widgets").changes_scanned_at
  end

  test "keeps the window and continues when one repository fails" do
    Shiplog.config.repositories = [ "Acme/widgets", "Acme/gadgets" ]
    stub_request(:post, GRAPHQL).with { |req| JSON.parse(req.body).dig("variables", "name") == "widgets" }
      .to_return(status: 500, body: "boom")
    stub_request(:post, GRAPHQL).with { |req| JSON.parse(req.body).dig("variables", "name") == "gadgets" }
      .to_return(body: github_fixture("commits"))

    Shiplog::ScanChangesJob.perform_now

    assert_nil Shiplog::Repository.find_by!(full_name: "Acme/widgets").changes_scanned_at
    assert Shiplog::Repository.find_by!(full_name: "Acme/gadgets").changes_scanned_at
  end
end
