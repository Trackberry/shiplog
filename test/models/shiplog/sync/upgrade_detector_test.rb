require "test_helper"

class Shiplog::Sync::UpgradeDetectorTest < ActiveSupport::TestCase
  GRAPHQL = "https://api.github.com/graphql".freeze
  COMPARE = "https://api.github.com/repos/Trackberry/market_data/compare".freeze
  BASE = "cb3cbf6b".freeze
  MERGE = "53e43492".freeze

  def lockfile(market_data: "0.2.1", holidays: "8.0.0", git_revision: nil)
    source = if git_revision
      "GIT\n  remote: https://github.com/Trackberry/market_data.git\n  revision: #{git_revision}\n  specs:\n    market_data (#{market_data})\n\n"
    else
      "GEM\n  remote: https://rubygems.pkg.github.com/Trackberry/\n  specs:\n    market_data (#{market_data})\n\n"
    end
    <<~LOCK
      #{source}GEM
        remote: https://rubygems.org/
        specs:
          holidays (#{holidays})

      PLATFORMS
        ruby

      DEPENDENCIES
        holidays
        market_data

      BUNDLED WITH
         2.5.0
    LOCK
  end

  setup do
    Shiplog.config.github_token = "tok"
    Shiplog.config.repositories = [
      "Trackberry/trackberry",
      { name: "Trackberry/market_data", changelog: false, gem: "market_data" }
    ]
    @repository = shiplog_repositories(:app)
    @pull_request = make_pull_request(number: 1952)
    @detector = Shiplog::Sync::UpgradeDetector.new(@repository, client: Shiplog::Github::Client.new(token: "tok", retry_delay: 0))
  end

  def make_pull_request(number:, **attributes)
    @repository.pull_requests.create!({ node_id: "PR_#{number}", number:, title: "Bump market_data", state: "merged",
      merged_at: Time.utc(2026, 10, 20, 10), author_login: "dependabot[bot]", labels: [], github_updated_at: Time.utc(2026, 10, 20),
      base_oid: BASE, merge_oid: MERGE, lockfile_changed: true }.merge(attributes))
  end

  def blob_requests = proc { |req| JSON.parse(req.body)["query"].include?("... on Blob") }

  def stub_blob(oid, text)
    body = { data: { repository: { object: text && { text: } } } }.to_json
    stub_request(:post, GRAPHQL).with { |req| JSON.parse(req.body).dig("variables", "expression") == "#{oid}:Gemfile.lock" }.to_return(body:)
  end

  def commit(sha) = { sha:, node_id: "C_#{sha}" }

  def stub_compare(from, to, commits)
    stub_request(:get, "#{COMPARE}/#{from}...#{to}").to_return(body: { commits: commits.map { |sha| commit(sha) } }.to_json)
  end

  def pr_node(number, title, body: "Body #{number}", state: "MERGED", repository: "Trackberry/market_data")
    { number:, title:, body:, url: "https://github.com/#{repository}/pull/#{number}", state:, repository: { nameWithOwner: repository } }
  end

  def stub_associated(by_sha)
    nodes = by_sha.map { |sha, prs| { oid: sha, associatedPullRequests: { nodes: prs } } }
    stub_request(:post, GRAPHQL).with { |req| JSON.parse(req.body)["query"].include?("associatedPullRequests(first: 5)") && JSON.parse(req.body)["query"].include?("nodes(ids") }
      .to_return(body: { data: { nodes: } }.to_json)
  end

  def stub_trackberry_1952
    stub_blob(BASE, lockfile)
    stub_blob(MERGE, lockfile(market_data: "0.2.2"))
    stub_request(:get, "#{COMPARE}/v0.2.1...v0.2.2").to_return(status: 404, body: "{}")
    stub_compare("0.2.1", "0.2.2", %w[c1 c2 c3 c4 c5 c6])
    stub_associated(
      "c1" => [ pr_node(38, "Gem publish workflow: fix the two run annotations") ],
      "c2" => [ pr_node(38, "Gem publish workflow: fix the two run annotations") ],
      "c3" => [ pr_node(39, "DIAN and SUNAT: remember files broken at the source, catch short downloads", body: "x" * 400) ],
      "c4" => [], "c5" => [ pr_node(40, "Not merged", state: "CLOSED") ], "c6" => [ pr_node(7, "Elsewhere", repository: "Trackberry/other") ]
    )
  end

  test "diffs the lockfiles, resolves the tags and stores the gem's pull requests" do
    stub_trackberry_1952

    @detector.call

    upgrade = @pull_request.upgrades.sole
    assert_equal %w[market_data 0.2.1 0.2.2 Trackberry/market_data], [ upgrade.gem_name, upgrade.from_ref, upgrade.to_ref, upgrade.gem_repository ]
    assert_equal [ 38, 39 ], upgrade.gem_changes.map { |change| change["number"] }
    assert_equal "Gem publish workflow: fix the two run annotations", upgrade.gem_changes.first["title"]
    assert_equal "https://github.com/Trackberry/market_data/pull/38", upgrade.gem_changes.first["url"]
    assert_equal 300, upgrade.gem_changes.last["body_excerpt"].length
    assert_predicate @pull_request.reload.upgrades_checked_at, :present?
  end

  test "tries the v-prefixed tag first" do
    stub_blob(BASE, lockfile)
    stub_blob(MERGE, lockfile(market_data: "0.2.2"))
    stub_compare("v0.2.1", "v0.2.2", %w[c1])
    stub_associated("c1" => [ pr_node(38, "T") ])

    @detector.call

    upgrade = @pull_request.upgrades.sole
    assert_equal %w[v0.2.1 v0.2.2], [ upgrade.from_ref, upgrade.to_ref ]
    assert_not_requested :get, "#{COMPARE}/0.2.1...0.2.2"
  end

  test "does not inspect a pull request that did not touch the lockfile" do
    @pull_request.update!(lockfile_changed: false)

    @detector.call

    assert_not_requested(:post, GRAPHQL)
    assert_nil @pull_request.reload.upgrades_checked_at
  end

  test "only inspects merged pull requests" do
    @pull_request.update!(state: "open")

    @detector.call

    assert_not_requested(:post, GRAPHQL)
  end

  test "skips an unchanged lockfile and marks the pull request checked" do
    stub_blob(BASE, lockfile)
    stub_blob(MERGE, lockfile)

    @detector.call

    assert_empty @pull_request.upgrades
    assert @pull_request.reload.upgrades_checked_at
  end

  test "ignores untracked gems such as the public holidays gem" do
    stub_blob(BASE, lockfile)
    stub_blob(MERGE, lockfile(holidays: "8.1.0"))

    @detector.call

    assert_empty @pull_request.upgrades
    assert_not_requested :get, /api.github.com\/repos/
    assert @pull_request.reload.upgrades_checked_at
  end

  test "a git-sourced gem uses revisions" do
    old_revision = "a" * 40
    new_revision = "b" * 40
    stub_blob(BASE, lockfile(market_data: "0.2.0", git_revision: old_revision))
    stub_blob(MERGE, lockfile(market_data: "0.2.0", git_revision: new_revision))
    stub_compare(old_revision, new_revision, %w[c1])
    stub_associated("c1" => [ pr_node(38, "T") ])

    @detector.call

    upgrade = @pull_request.upgrades.sole
    assert_equal [ old_revision, new_revision ], [ upgrade.from_ref, upgrade.to_ref ]
    assert_equal [ 38 ], upgrade.gem_changes.map { |change| change["number"] }
  end

  test "a git source moving to a released version compares a revision with the tag" do
    old_revision = "a" * 40
    stub_blob(BASE, lockfile(market_data: "0.2.0", git_revision: old_revision))
    stub_blob(MERGE, lockfile(market_data: "0.2.2"))
    stub_compare(old_revision, "v0.2.2", %w[c1])
    stub_associated("c1" => [ pr_node(38, "T") ])

    @detector.call

    assert_equal [ old_revision, "v0.2.2" ], @pull_request.upgrades.sole.then { |upgrade| [ upgrade.from_ref, upgrade.to_ref ] }
  end

  test "an unresolvable tag records the upgrade without changes and warns" do
    stub_blob(BASE, lockfile)
    stub_blob(MERGE, lockfile(market_data: "0.2.2"))
    stub_request(:get, /#{Regexp.escape(COMPARE)}/).to_return(status: 404, body: "{}")
    io = StringIO.new

    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    begin
      @detector.call
    ensure
      Rails.logger = original
    end

    upgrade = @pull_request.upgrades.sole
    assert_equal [], upgrade.gem_changes
    assert_equal %w[0.2.1 0.2.2], [ upgrade.from_ref, upgrade.to_ref ]
    assert_match(/market_data.*0\.2\.1.*0\.2\.2/, io.string)
    assert @pull_request.reload.upgrades_checked_at
  end

  test "caps the stored changes at 50 and de-duplicates them" do
    stub_blob(BASE, lockfile)
    stub_blob(MERGE, lockfile(market_data: "0.2.2"))
    shas = (1..60).map { |i| "c#{i}" }
    stub_compare("v0.2.1", "v0.2.2", shas)
    stub_associated(shas.to_h { |sha| [ sha, [ pr_node(sha[1..].to_i, "PR #{sha}"), pr_node(1, "PR c1") ] ] })

    @detector.call

    numbers = @pull_request.upgrades.sole.gem_changes.map { |change| change["number"] }
    assert_equal 50, numbers.size
    assert_equal numbers.uniq, numbers
    assert_equal (1..50).to_a, numbers
  end

  test "is idempotent: a checked pull request is not inspected again and the upsert keeps one row" do
    stub_trackberry_1952
    @detector.call
    assert_requested(:post, GRAPHQL, times: 3)

    @detector.call
    assert_requested(:post, GRAPHQL, times: 3)

    @pull_request.update!(upgrades_checked_at: nil)
    @detector.call
    assert_equal 1, @pull_request.upgrades.count
  end

  test "handles at most 50 pull requests per call, newest first, and finishes the rest on the next call" do
    @pull_request.destroy!
    stub_request(:post, GRAPHQL).with(&blob_requests).to_return(body: { data: { repository: { object: { text: lockfile } } } }.to_json)
    60.times { |i| make_pull_request(number: 100 + i, merged_at: Time.utc(2026, 9, 1) + i.hours) }

    assert_equal 50, @detector.call
    assert_equal 10, @repository.pull_requests.awaiting_upgrade_check.count
    assert_equal (100..109).to_a, @repository.pull_requests.awaiting_upgrade_check.map(&:number).sort

    assert_equal 10, @detector.call
    assert_equal 0, @repository.pull_requests.awaiting_upgrade_check.count
  end

  test "a lockfile missing on one side records nothing" do
    stub_blob(BASE, nil)
    stub_blob(MERGE, lockfile)

    @detector.call

    assert_empty @pull_request.upgrades
    assert @pull_request.reload.upgrades_checked_at
  end

  test "rate limits propagate and leave the pull request unchecked" do
    stub_request(:post, GRAPHQL).to_return(status: 429, headers: { "retry-after" => "30" })

    assert_raises(Shiplog::Github::RateLimited) { @detector.call }
    assert_nil @pull_request.reload.upgrades_checked_at
  end

  test "repositories with changelog: false are not inspected" do
    Shiplog.config.repositories = [ { name: "Trackberry/trackberry", changelog: false } ]

    assert_equal 0, @detector.call
    assert_not_requested(:post, GRAPHQL)
  end

  test "does nothing when no gem is tracked" do
    Shiplog.config.repositories = [ "Trackberry/trackberry" ]

    assert_equal 0, @detector.call
    assert_not_requested(:post, GRAPHQL)
    assert_nil @pull_request.reload.upgrades_checked_at
  end
end
