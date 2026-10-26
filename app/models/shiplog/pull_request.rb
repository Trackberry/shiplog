module Shiplog
  class PullRequest < ApplicationRecord
    belongs_to :repository
    has_many :issue_links, primary_key: :node_id, foreign_key: :pull_request_node_id, dependent: :delete_all
    has_many :issues, through: :issue_links
    has_many :entries, as: :subject, dependent: :destroy
    has_many :upgrades, class_name: "Shiplog::PullRequestUpgrade", dependent: :destroy

    # Merged pull requests that touched the lockfile and were not inspected yet, newest first.
    scope :awaiting_upgrade_check, -> { where(state: "merged", lockfile_changed: true, upgrades_checked_at: nil).order(merged_at: :desc, id: :desc) }

    def open? = state == "open"
    def merged? = state == "merged"
  end
end
