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

  def upgrade(pull_request, changes: [ { "number" => 38, "title" => "Fix annotations", "body_excerpt" => "x", "url" => "u" } ], gem_name: "market_data")
    Shiplog::PullRequestUpgrade.create!(pull_request:, gem_name:, from_ref: "0.2.1", to_ref: "0.2.2", gem_repository: "Trackberry/market_data", gem_changes: changes)
  end

  test "a pull request with a tracked upgrade is a candidate despite bot author, chore type and dependencies label" do
    bump = pull_request(80, title: "chore(deps): Bump market_data from 0.2.1 to 0.2.2", author_login: "dependabot[bot]", labels: [ "dependencies" ])
    upgrade(bump)

    assert_includes candidates, bump
  end

  test "an upgrade bypasses the dependencies label only: an internal label still excludes it" do
    internal = pull_request(83, title: "chore(deps): Bump market_data", author_login: "dependabot[bot]", labels: [ "dependencies", "internal" ])
    upgrade(internal)

    assert_not_includes candidates, internal
  end

  test "a pull request awaiting its upgrade check is held back, neither a candidate nor excluded for good" do
    Shiplog.config.repositories = [ "Trackberry/trackberry", { name: "Trackberry/market_data", changelog: false, gem: "market_data" } ]
    bump = pull_request(84, title: "chore(deps): Bump market_data", author_login: "dependabot[bot]", labels: [ "dependencies" ],
      lockfile_changed: true, upgrades_checked_at: nil)
    plain = pull_request(85, lockfile_changed: true, upgrades_checked_at: nil)

    assert_empty candidates & [ bump, plain ]

    bump.update!(upgrades_checked_at: Time.utc(2026, 10, 11))
    upgrade(bump)
    plain.update!(upgrades_checked_at: Time.utc(2026, 10, 11))

    assert_equal [ bump, plain ].to_set, (candidates & [ bump, plain ]).to_set
  end

  test "pending pull requests are not held when no gem is tracked, since detection would never run" do
    Shiplog.config.repositories = [ "Trackberry/trackberry" ]
    plain = pull_request(86, lockfile_changed: true, upgrades_checked_at: nil)

    assert_includes candidates, plain
  end

  test "bots, chore types and excluded labels are still excluded without an upgrade" do
    plain = pull_request(81, title: "chore(deps): Bump rails", author_login: "dependabot[bot]", labels: [ "dependencies" ])
    empty = pull_request(82, title: "chore(deps): Bump seaports", author_login: "dependabot[bot]", labels: [ "dependencies" ])
    upgrade(empty, changes: [])

    assert_empty candidates & [ plain, empty ]
  end

  test "keeps PR titles that only start with a topic, not a conventional type" do
    topic = pull_request(61, title: "Importers: merge keys across exporters")
    scoped = pull_request(62, title: "Callao: read manifests whole")
    chore = pull_request(63, title: "chore: Tidy the Gemfile")

    assert_equal [ topic, scoped ], candidates & [ topic, scoped, chore ]
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

  test "a PR whose entry was switched to a feature is not proposed again" do
    pr = pull_request(51)
    entry = Shiplog::Entry.create!(kind: "change", subject: pr, title: "Switched")
    entry.update!(changelog_kind: "feature")

    assert_not_includes candidates, pr
  end
end
