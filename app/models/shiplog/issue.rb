module Shiplog
  class Issue < ApplicationRecord
    COLUMNS = %w[in_progress coming_soon later].freeze

    belongs_to :repository
    belongs_to :parent, class_name: "Shiplog::Issue", primary_key: :node_id, foreign_key: :parent_node_id, optional: true
    has_many :children, class_name: "Shiplog::Issue", primary_key: :node_id, foreign_key: :parent_node_id
    has_many :issue_links, primary_key: :node_id, foreign_key: :issue_node_id, dependent: :delete_all
    has_many :linked_pull_requests, through: :issue_links, source: :pull_request
    has_many :entries, as: :subject, dependent: :destroy

    enum :pinned_column, COLUMNS.index_by(&:itself), prefix: :pinned, validate: { allow_nil: true }

    scope :open, -> { where(state: "open") }
    scope :labeled, ->(name) { where("labels @> ?", [ name ].to_json) }
    scope :publicly_labeled, -> { labeled(Shiplog.config.public_label) }

    def public? = labels.include?(Shiplog.config.public_label)
    def open? = state == "open"

    def descendants
      children.flat_map { |child| [ child, *child.descendants ] }
    end
  end
end
