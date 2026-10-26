require "test_helper"

class Shiplog::ChangeCandidatesTest < ActiveSupport::TestCase
  SINCE = Time.utc(2026, 10, 1)
  BEFORE = Time.utc(2026, 10, 20)

  setup { @repository = shiplog_repositories(:app) }

  def candidates(since: SINCE, before: BEFORE)
    Shiplog::ChangeCandidates.new(repository: @repository, since:, before:).to_a
  end

  def pull_request(number, **attributes)
    Shiplog::PullRequest.create!({ repository: @repository, node_id: "PR_t#{number}", number:, title: "PR #{number}", state: "merged",
      merged_at: Time.utc(2026, 10, 10), author_login: "edouard", labels: [], github_updated_at: Time.utc(2026, 10, 10) }.merge(attributes))
  end

  def commit(sha_char, message, **attributes)
    @repository.commits.create!({ sha: sha_char * 40, message:, author_login: "edouard", committed_at: Time.utc(2026, 10, 10) }.merge(attributes))
  end

  def link(issue_node_id, pull_request)
    Shiplog::IssueLink.create!(issue_node_id:, pull_request_node_id: pull_request.node_id)
  end

  test "includes merged PRs in the window" do
    pr = pull_request(50)

    assert_includes candidates, pr
  end

  test "excludes PRs outside the window or not merged" do
    outside = pull_request(51, merged_at: Time.utc(2026, 9, 1))
    later = pull_request(52, merged_at: Time.utc(2026, 10, 25))
    closed = pull_request(53, state: "closed", merged_at: nil)

    assert_empty candidates & [ outside, later, closed ]
  end

  test "excludes PRs with an excluded label" do
    assert_not_includes candidates, pull_request(54, labels: [ "chore" ])
  end

  test "excludes PRs whose conventional type is not a changelog type" do
    ci = pull_request(57, title: "ci: Cache gems")
    chore = pull_request(58, title: "chore(deps): Bump rails")
    fix = pull_request(59, title: "fix(mailbox): Accept forwarded mail")
    untyped = pull_request(60, title: "Read prices from the new feed")

    assert_equal [ fix, untyped ], candidates & [ ci, chore, fix, untyped ]
  end

  test "excludes bot authors" do
    assert_not_includes candidates, pull_request(55, author_login: "dependabot[bot]")
  end

  test "excludes PRs linked to a public issue" do
    pr = pull_request(56)
    link("I_export_report", pr)

    assert_not_includes candidates, pr
  end

  test "excludes PRs linked to a child of a public parent" do
    pr = pull_request(57)
    link("I_bulk_upload_csv_validation", pr)

    assert_not_includes candidates, pr
  end

  test "excludes PRs linked to a non-public child of a public ancestor several levels up" do
    middle = shiplog_issues(:refactor_db)
    middle.update!(parent_node_id: "I_bulk_upload")
    leaf = Shiplog::Issue.create!(repository: @repository, node_id: "I_leaf", number: 200, title: "Leaf", labels: [], parent_node_id: middle.node_id,
      github_created_at: Time.current, github_updated_at: Time.current)
    pr = pull_request(58)
    link(leaf.node_id, pr)

    assert_not_includes candidates, pr
  end

  test "includes PRs linked only to private issues" do
    pr = pull_request(59)
    link("I_refactor_db", pr)

    assert_includes candidates, pr
  end

  test "survives parent cycles" do
    a = Shiplog::Issue.create!(repository: @repository, node_id: "I_a", number: 201, title: "A", labels: [], parent_node_id: "I_b",
      github_created_at: Time.current, github_updated_at: Time.current)
    Shiplog::Issue.create!(repository: @repository, node_id: "I_b", number: 202, title: "B", labels: [], parent_node_id: a.node_id,
      github_created_at: Time.current, github_updated_at: Time.current)
    pr = pull_request(60)
    link(a.node_id, pr)

    assert_includes candidates, pr
  end

  test "excludes PRs that already have an entry of any kind" do
    pr = pull_request(61)
    Shiplog::Entry.create!(subject: pr, kind: "change", status: "discarded")

    assert_not_includes candidates, pr
  end

  test "includes commits with conventional types and excludes others" do
    kept = [ commit("a", "feat: add x"), commit("b", "fix(scope): y"), commit("c", "perf!: z"), commit("g", "feat!: breaking"), commit("h", "feat(api)!: breaking scoped") ]
    dropped = [ commit("d", "chore: bump"), commit("e", "test: add"), commit("f", "plain message") ]

    result = candidates
    assert_empty kept - result
    assert_empty dropped & result
  end

  test "excludes commits by excluded authors and with existing entries" do
    bot = commit("8", "fix: x", author_login: "github-actions[bot]")
    done = commit("9", "fix: y")
    Shiplog::Entry.create!(subject: done, kind: "change")

    assert_empty candidates & [ bot, done ]
  end

  test "excludes commits outside the window" do
    assert_not_includes candidates, commit("3", "fix: old", committed_at: Time.utc(2026, 9, 1))
  end

  test "uses a bounded number of queries" do
    5.times { |i| link("I_refactor_db", pull_request(70 + i)) }
    count = 0
    callback = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { candidates }

    assert_operator count, :<=, 10
  end
end
