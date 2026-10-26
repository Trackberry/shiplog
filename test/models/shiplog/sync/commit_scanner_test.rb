require "test_helper"

class Shiplog::Sync::CommitScannerTest < ActiveSupport::TestCase
  setup do
    @repository = Shiplog::Repository.create!(full_name: "Acme/widgets")
    @stub = stub_request(:post, "https://api.github.com/graphql").to_return(body: github_fixture("commits"))
    @scanner = Shiplog::Sync::CommitScanner.new(@repository, client: Shiplog::Github::Client.new(token: "tok"))
  end

  test "stores only commits without an associated pull request" do
    @scanner.call(since: Time.utc(2026, 10, 1))

    assert_equal [ "a" * 40, "c" * 40 ], @repository.commits.order(:sha).pluck(:sha)
    commit = @repository.commits.find_by!(sha: "a" * 40)
    assert_equal "fix: direct push", commit.title
    assert_equal "octocat", commit.author_login
    assert_equal Time.utc(2026, 10, 12, 8), commit.committed_at
    assert_nil @repository.commits.find_by!(sha: "c" * 40).author_login
  end

  test "sends since and is idempotent" do
    2.times { @scanner.call(since: Time.utc(2026, 10, 1)) }

    assert_equal 2, @repository.commits.count
    assert_requested(:post, "https://api.github.com/graphql", times: 2) { |req| JSON.parse(req.body).dig("variables", "since") == "2026-10-01T00:00:00Z" }
  end

  test "does nothing for a repository without a default branch" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(body: { data: { repository: { defaultBranchRef: nil } } }.to_json)

    assert_nothing_raised { @scanner.call(since: nil) }
    assert_equal 0, @repository.commits.count
  end
end
