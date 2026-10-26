module Shiplog
  class PullRequest < ApplicationRecord
    belongs_to :repository
    has_many :issue_links, primary_key: :node_id, foreign_key: :pull_request_node_id, dependent: :delete_all
    has_many :issues, through: :issue_links
    has_many :entries, as: :subject, dependent: :destroy

    def open? = state == "open"
    def merged? = state == "merged"
  end
end
