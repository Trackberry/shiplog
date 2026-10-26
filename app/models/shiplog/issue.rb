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
    scope :labeled, ->(name) { where("#{table_name}.labels @> ?", [ name ].to_json) }
    scope :publicly_labeled, -> { labeled(Shiplog.config.public_label) }

    def public? = labels.include?(Shiplog.config.public_label)
    def open? = state == "open"

    MAX_DEPTH = 8

    # Loads every descendant of the roots breadth-first, one query per level.
    # Returns a hash of parent node_id => children.
    def self.children_index(roots)
      index = Hash.new { |hash, key| hash[key] = [] }
      visited = roots.map(&:node_id).to_set
      frontier = visited.to_a

      MAX_DEPTH.times do
        break if frontier.empty?
        level = where(parent_node_id: frontier).to_a
        frontier = []
        level.each do |child|
          index[child.parent_node_id] << child
          frontier << child.node_id if visited.add?(child.node_id)
        end
      end
      index
    end

    def self.descendants_in(index, root)
      visited = Set[root.node_id]
      frontier = [ root ]
      found = []
      MAX_DEPTH.times do
        frontier = frontier.flat_map { |issue| index.fetch(issue.node_id, []) }
          .select { |child| visited.add?(child.node_id) }
        found.concat(frontier)
      end
      found
    end

    def descendants
      visited = Set[node_id]
      frontier = [ node_id ]
      found = []
      MAX_DEPTH.times do
        break if frontier.empty?
        level = self.class.where(parent_node_id: frontier).where.not(node_id: visited.to_a).to_a
        level = level.select { |issue| visited.add?(issue.node_id) }
        found.concat(level)
        frontier = level.map(&:node_id)
      end
      found
    end
  end
end
