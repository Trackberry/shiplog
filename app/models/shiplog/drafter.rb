module Shiplog
  module Drafter
    # Only issues closed within this window get a feature draft, so a first-run backfill
    # cannot flood the inbox with years-old work. Recently closed issues are still backfilled.
    FEATURE_LOOKBACK = 90.days

    def self.call
      draft_roadmap_items
      draft_shipped_features
    end

    # Returns the new entry, or nil when one already exists for the subject and kind.
    def self.draft(subject, kind, released_on: nil)
      entry = Entry.create_or_find_by!(subject:, kind:) do |new_entry|
        new_entry.title = subject.title
        new_entry.body = subject.body
        new_entry.released_on = released_on
      end
      return unless entry.previously_new_record?

      RewriteEntryJob.perform_later(entry.id)
      entry
    end

    def self.draft_roadmap_items
      Roadmap.new(published_only: false).items.each do |item|
        draft(item.issue, "roadmap") unless item.entry
      end
    end

    def self.draft_shipped_features
      issues = shipped_candidates
      return if issues.empty?

      index = Issue.children_index(issues)
      merged_at_by_issue = merged_at_by_issue_node_id(issues, index)
      issues.each do |issue|
        tree = [ issue, *Issue.descendants_in(index, issue) ]
        merged_at = tree.filter_map { |member| merged_at_by_issue[member.node_id] }.max
        draft(issue, "feature", released_on: merged_at.to_date) if merged_at
      end
    end

    def self.shipped_candidates
      drafted = Entry.feature.where(subject_type: Issue.name).select(:subject_id)
      Issue.publicly_labeled.where(state: "closed", state_reason: "completed", closed_at: FEATURE_LOOKBACK.ago..)
        .where.not(id: drafted)
        .includes(:parent).reject { |issue| issue.parent&.public? }
    end

    def self.merged_at_by_issue_node_id(issues, index)
      node_ids = issues.map(&:node_id) + index.values.flatten.map(&:node_id)
      IssueLink.where(issue_node_id: node_ids.uniq).joins(:pull_request).merge(PullRequest.where(state: "merged"))
        .group(:issue_node_id).maximum(PullRequest.arel_table[:merged_at])
    end

    private_class_method :draft_roadmap_items, :draft_shipped_features, :shipped_candidates, :merged_at_by_issue_node_id
  end
end
