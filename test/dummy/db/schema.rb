# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_27_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "shiplog_commits", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.string "sha", null: false
    t.text "message", null: false
    t.string "author_login"
    t.datetime "committed_at"
    t.string "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id", "sha"], name: "index_shiplog_commits_on_repository_id_and_sha", unique: true
  end

  create_table "shiplog_entries", force: :cascade do |t|
    t.string "kind", null: false
    t.string "status", default: "draft", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "title"
    t.text "body"
    t.string "source_digest"
    t.datetime "rewritten_at"
    t.text "rewrite_error"
    t.date "released_on"
    t.datetime "approved_at"
    t.string "approved_by"
    t.string "discard_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_shiplog_entries_on_status"
    t.index ["subject_type", "subject_id", "kind"], name: "index_shiplog_entries_on_subject_type_and_subject_id_and_kind", unique: true
  end

  create_table "shiplog_issue_links", force: :cascade do |t|
    t.string "issue_node_id", null: false
    t.string "pull_request_node_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["issue_node_id", "pull_request_node_id"], name: "idx_on_issue_node_id_pull_request_node_id_5a84592f9b", unique: true
    t.index ["pull_request_node_id"], name: "index_shiplog_issue_links_on_pull_request_node_id"
  end

  create_table "shiplog_issues", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.string "node_id", null: false
    t.integer "number", null: false
    t.string "title", null: false
    t.text "body"
    t.string "state", default: "open", null: false
    t.string "state_reason"
    t.jsonb "labels", default: [], null: false
    t.string "milestone_title"
    t.integer "assignees_count", default: 0, null: false
    t.string "parent_node_id"
    t.string "url"
    t.datetime "github_created_at"
    t.datetime "github_updated_at"
    t.datetime "closed_at"
    t.string "pinned_column"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["labels"], name: "index_shiplog_issues_on_labels", using: :gin
    t.index ["node_id"], name: "index_shiplog_issues_on_node_id", unique: true
    t.index ["parent_node_id"], name: "index_shiplog_issues_on_parent_node_id"
    t.index ["repository_id"], name: "index_shiplog_issues_on_repository_id"
  end

  create_table "shiplog_pull_request_upgrades", force: :cascade do |t|
    t.bigint "pull_request_id", null: false
    t.string "gem_name", null: false
    t.string "from_ref"
    t.string "to_ref"
    t.string "gem_repository"
    t.jsonb "gem_changes", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_id", "gem_name"], name: "idx_on_pull_request_id_gem_name_9004c057ce", unique: true
  end

  create_table "shiplog_pull_requests", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.string "node_id", null: false
    t.integer "number", null: false
    t.string "title", null: false
    t.text "body"
    t.string "state", default: "open", null: false
    t.datetime "merged_at"
    t.string "author_login"
    t.jsonb "labels", default: [], null: false
    t.string "url"
    t.datetime "github_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "base_oid"
    t.string "merge_oid"
    t.boolean "lockfile_changed", default: false, null: false
    t.datetime "upgrades_checked_at"
    t.index ["node_id"], name: "index_shiplog_pull_requests_on_node_id", unique: true
    t.index ["repository_id"], name: "index_shiplog_pull_requests_on_repository_id"
  end

  create_table "shiplog_repositories", force: :cascade do |t|
    t.string "full_name", null: false
    t.datetime "synced_at"
    t.datetime "sync_cursor"
    t.datetime "changes_scanned_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["full_name"], name: "index_shiplog_repositories_on_full_name", unique: true
  end

  create_table "shiplog_webhook_deliveries", force: :cascade do |t|
    t.string "delivery_id", null: false
    t.string "event"
    t.string "action"
    t.string "repository_full_name"
    t.datetime "received_at"
    t.datetime "processed_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_shiplog_webhook_deliveries_on_delivery_id", unique: true
  end

  add_foreign_key "shiplog_commits", "shiplog_repositories", column: "repository_id"
  add_foreign_key "shiplog_issues", "shiplog_repositories", column: "repository_id"
  add_foreign_key "shiplog_pull_request_upgrades", "shiplog_pull_requests", column: "pull_request_id"
  add_foreign_key "shiplog_pull_requests", "shiplog_repositories", column: "repository_id"
end
