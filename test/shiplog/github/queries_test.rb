require "test_helper"

class Shiplog::Github::QueriesTest < ActiveSupport::TestCase
  Shiplog::Github::Queries::ALL.each do |name, document|
    test "#{name} defines exactly the fragments it uses" do
      defined = document.scan(/^\s*fragment\s+(\w+)\s+on\s/).flatten
      assert_equal defined.uniq, defined, "duplicate fragment definitions"

      # Spreads reachable from the operation body (outside fragment definitions).
      operation = document.split(/^\s*fragment\s/).first
      used = reachable_spreads(operation, document)

      assert_equal used.sort, defined.sort
    end
  end

  test "queries include the required connections" do
    assert_includes Shiplog::Github::Queries::ISSUES, "closedByPullRequestsReferences(first: 20, includeClosedPrs: true)"
    assert_includes Shiplog::Github::Queries::PULL_REQUESTS, "closingIssuesReferences"
    assert_includes Shiplog::Github::Queries::COMMITS, "associatedPullRequests(first: 1)"
  end

  test "pull request queries request what upgrade detection needs" do
    [ Shiplog::Github::Queries::PULL_REQUESTS, Shiplog::Github::Queries::PULL_REQUEST ].each do |query|
      assert_includes query, "baseRefOid"
      assert_includes query, "mergeCommit { oid parents(first: 1) { nodes { oid } } }"
      assert_includes query, "files(first: 100) { pageInfo { hasNextPage } nodes { path } }"
    end
    assert_includes Shiplog::Github::Queries::BLOB_TEXT, "object(expression: $expression)"
    assert_includes Shiplog::Github::Queries::BLOB_TEXT, "... on Blob"
    assert_includes Shiplog::Github::Queries::COMMIT_PULL_REQUESTS, "associatedPullRequests"
  end

  test "link connections request pageInfo hasNextPage" do
    assert_match(/closedByPullRequestsReferences\([^)]*\) \{\s*pageInfo \{ hasNextPage \}/, Shiplog::Github::Queries::ISSUES)
    assert_match(/closingIssuesReferences\([^)]*\) \{\s*pageInfo \{ hasNextPage \}/, Shiplog::Github::Queries::PULL_REQUESTS)
  end

  private

  # Follows spreads transitively; fails if a spread has no definition.
  def reachable_spreads(text, document, seen = [])
    text.scan(/\.\.\.(\w+)/).flatten.each do |spread|
      next if seen.include?(spread)

      body = document[/^\s*fragment\s+#{spread}\s+on\s.*?(?=^\s*fragment\s|\z)/m]
      assert body, "spread ...#{spread} has no definition"
      seen << spread
      reachable_spreads(body, document, seen)
    end
    seen
  end
end
