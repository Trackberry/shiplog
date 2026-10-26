module Shiplog
  module Github
    module Queries
      FRAGMENTS = <<~GRAPHQL.freeze
        fragment PullRequestFields on PullRequest {
          id number title body state mergedAt url updatedAt
          author { login }
          repository { nameWithOwner }
          labels(first: 30) { nodes { name } }
        }
        fragment IssueFields on Issue {
          id number title body state stateReason url createdAt updatedAt closedAt
          labels(first: 30) { nodes { name } }
          milestone { title }
          assignees { totalCount }
          parent { id }
          closedByPullRequestsReferences(first: 20, includeClosedPrs: true) {
            nodes { ...PullRequestFields }
          }
        }
        fragment PullRequestWithIssues on PullRequest {
          ...PullRequestFields
          closingIssuesReferences(first: 20) { nodes { id } }
        }
      GRAPHQL

      ISSUES = <<~GRAPHQL.freeze
        query($owner: String!, $name: String!, $since: DateTime, $after: String) {
          repository(owner: $owner, name: $name) {
            issues(first: 50, after: $after, filterBy: { since: $since }, orderBy: { field: UPDATED_AT, direction: ASC }) {
              pageInfo { hasNextPage endCursor }
              nodes { ...IssueFields }
            }
          }
        }
        #{FRAGMENTS}
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
        #{FRAGMENTS}
      GRAPHQL

      ISSUE = <<~GRAPHQL.freeze
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            issue(number: $number) { ...IssueFields }
          }
        }
        #{FRAGMENTS}
      GRAPHQL

      PULL_REQUEST = <<~GRAPHQL.freeze
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) { ...PullRequestWithIssues }
          }
        }
        #{FRAGMENTS}
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
    end
  end
end
