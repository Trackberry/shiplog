module Shiplog
  module Github
    module Queries
      PULL_REQUEST_FIELDS = <<~GRAPHQL.freeze
        fragment PullRequestFields on PullRequest {
          id number title body state mergedAt url updatedAt
          author { __typename login }
          repository { nameWithOwner }
          labels(first: 30) { nodes { name } }
        }
      GRAPHQL

      ISSUE_FIELDS = <<~GRAPHQL.freeze
        fragment IssueFields on Issue {
          __typename id number title body state stateReason url createdAt updatedAt closedAt
          labels(first: 30) { nodes { name } }
          milestone { title }
          assignees { totalCount }
          parent { id }
          closedByPullRequestsReferences(first: 20, includeClosedPrs: true) {
            pageInfo { hasNextPage }
            nodes { ...PullRequestFields }
          }
        }
      GRAPHQL

      PULL_REQUEST_WITH_ISSUES = <<~GRAPHQL.freeze
        fragment PullRequestWithIssues on PullRequest {
          ...PullRequestFields
          closingIssuesReferences(first: 20) {
            pageInfo { hasNextPage }
            nodes { id }
          }
        }
      GRAPHQL

      # GitHub rejects documents with unused fragments, so each query embeds
      # exactly the fragments it (transitively) uses.
      ISSUE_FRAGMENTS = (ISSUE_FIELDS + PULL_REQUEST_FIELDS).freeze
      PULL_REQUEST_FRAGMENTS = (PULL_REQUEST_WITH_ISSUES + PULL_REQUEST_FIELDS).freeze

      ISSUES = <<~GRAPHQL.freeze
        query($owner: String!, $name: String!, $since: DateTime, $after: String) {
          repository(owner: $owner, name: $name) {
            issues(first: 50, after: $after, filterBy: { since: $since }, orderBy: { field: UPDATED_AT, direction: ASC }) {
              pageInfo { hasNextPage endCursor }
              nodes { ...IssueFields }
            }
          }
        }
        #{ISSUE_FRAGMENTS}
      GRAPHQL

      PULL_REQUESTS = <<~GRAPHQL.freeze
        query($owner: String!, $name: String!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequests(first: 50, after: $after, orderBy: { field: UPDATED_AT, direction: DESC }) {
              pageInfo { hasNextPage endCursor }
              nodes { ...PullRequestWithIssues }
            }
          }
        }
        #{PULL_REQUEST_FRAGMENTS}
      GRAPHQL

      ISSUE = <<~GRAPHQL.freeze
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            issue(number: $number) { ...IssueFields }
          }
        }
        #{ISSUE_FRAGMENTS}
      GRAPHQL

      PULL_REQUEST = <<~GRAPHQL.freeze
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) { ...PullRequestWithIssues }
          }
        }
        #{PULL_REQUEST_FRAGMENTS}
      GRAPHQL

      COMMITS = <<~GRAPHQL.freeze
        query($owner: String!, $name: String!, $since: GitTimestamp, $after: String) {
          repository(owner: $owner, name: $name) {
            defaultBranchRef {
              target {
                ... on Commit {
                  history(first: 100, since: $since, after: $after) {
                    pageInfo { hasNextPage endCursor }
                    nodes {
                      oid message committedDate url
                      author { user { login } }
                      associatedPullRequests(first: 1) { totalCount }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      ALL = { ISSUES:, PULL_REQUESTS:, ISSUE:, PULL_REQUEST:, COMMITS: }.freeze
    end
  end
end
