class CreateShiplogTables < ActiveRecord::Migration[8.1]
  def change
    create_table :shiplog_repositories do |t|
      t.string :full_name, null: false
      t.datetime :synced_at
      t.datetime :sync_cursor
      t.datetime :changes_scanned_at
      t.text :last_error
      t.timestamps
      t.index :full_name, unique: true
    end

    create_table :shiplog_issues do |t|
      t.references :repository, null: false, foreign_key: { to_table: :shiplog_repositories }
      t.string :node_id, null: false
      t.integer :number, null: false
      t.string :title, null: false
      t.text :body
      t.string :state, null: false, default: "open"
      t.string :state_reason
      t.jsonb :labels, null: false, default: []
      t.string :milestone_title
      t.integer :assignees_count, null: false, default: 0
      t.string :parent_node_id
      t.string :url
      t.datetime :github_created_at
      t.datetime :github_updated_at
      t.datetime :closed_at
      t.string :pinned_column
      t.integer :position
      t.timestamps
      t.index :node_id, unique: true
      t.index :parent_node_id
      t.index :labels, using: :gin
    end

    create_table :shiplog_pull_requests do |t|
      t.references :repository, null: false, foreign_key: { to_table: :shiplog_repositories }
      t.string :node_id, null: false
      t.integer :number, null: false
      t.string :title, null: false
      t.text :body
      t.string :state, null: false, default: "open"
      t.datetime :merged_at
      t.string :author_login
      t.jsonb :labels, null: false, default: []
      t.string :url
      t.datetime :github_updated_at
      t.timestamps
      t.index :node_id, unique: true
    end

    create_table :shiplog_issue_links do |t|
      t.string :issue_node_id, null: false
      t.string :pull_request_node_id, null: false
      t.timestamps
      t.index [ :issue_node_id, :pull_request_node_id ], unique: true
      t.index :pull_request_node_id
    end

    create_table :shiplog_commits do |t|
      t.references :repository, null: false, foreign_key: { to_table: :shiplog_repositories }, index: false
      t.string :sha, null: false
      t.text :message, null: false
      t.string :author_login
      t.datetime :committed_at
      t.string :url
      t.timestamps
      t.index [ :repository_id, :sha ], unique: true
    end

    create_table :shiplog_entries do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: "draft"
      t.references :subject, polymorphic: true, null: false, index: false
      t.string :title
      t.text :body
      t.string :source_digest
      t.datetime :rewritten_at
      t.text :rewrite_error
      t.date :released_on
      t.datetime :approved_at
      t.string :approved_by
      t.string :discard_reason
      t.timestamps
      t.index [ :subject_type, :subject_id, :kind ], unique: true
      t.index :status
    end

    create_table :shiplog_webhook_deliveries do |t|
      t.string :delivery_id, null: false
      t.string :event
      t.string :action
      t.string :repository_full_name
      t.datetime :received_at
      t.datetime :processed_at
      t.text :error
      t.timestamps
      t.index :delivery_id, unique: true
    end
  end
end
