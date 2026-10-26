module Shiplog
  class IssueLink < ApplicationRecord
    belongs_to :issue, primary_key: :node_id, foreign_key: :issue_node_id, optional: true
    belongs_to :pull_request, primary_key: :node_id, foreign_key: :pull_request_node_id, optional: true
  end
end
