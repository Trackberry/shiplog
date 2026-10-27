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

ActiveRecord::Schema[8.1].define(version: 2026_10_28_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "shiplog_areas", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "name_translations", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_shiplog_areas_on_slug", unique: true
  end

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
    t.string "slug"
    t.bigint "area_id"
    t.boolean "area_set_by_admin", default: false, null: false
    t.datetime "area_detected_at"
    t.jsonb "image_order", default: [], null: false
    t.jsonb "image_alts", default: {}, null: false
    t.datetime "announced_at"
    t.index ["area_id"], name: "index_shiplog_entries_on_area_id"
    t.index ["slug"], name: "index_shiplog_entries_on_slug", unique: true, where: "(slug IS NOT NULL)"
    t.index ["status"], name: "index_shiplog_entries_on_status"
    t.index ["status", "approved_at"], name: "index_shiplog_entries_on_status_and_approved_at"
    t.index ["status", "released_on"], name: "index_shiplog_entries_on_status_and_released_on"
    t.index ["subject_type", "subject_id", "kind"], name: "index_shiplog_entries_on_subject_type_and_subject_id_and_kind", unique: true
  end

  create_table "shiplog_entry_translations", force: :cascade do |t|
    t.bigint "entry_id", null: false
    t.string "locale", null: false
    t.string "title", null: false
    t.text "body", default: "", null: false
    t.string "source_digest", null: false
    t.boolean "edited_by_admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entry_id", "locale"], name: "index_shiplog_entry_translations_on_entry_id_and_locale", unique: true
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

  create_table "shiplog_newsletter_deliveries", force: :cascade do |t|
    t.bigint "announcement_id", null: false
    t.string "recipient_key", null: false
    t.string "locale", null: false
    t.string "status", default: "pending", null: false
    t.datetime "sent_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["announcement_id", "recipient_key"], name: "index_shiplog_newsletter_deliveries_on_announcement_and_key", unique: true
    t.index ["announcement_id", "status"], name: "index_shiplog_newsletter_deliveries_on_announcement_and_status"
    t.index ["created_at"], name: "index_shiplog_newsletter_deliveries_on_created_at"
    t.index ["recipient_key"], name: "index_shiplog_newsletter_deliveries_on_recipient_key"
  end

  create_table "shiplog_newsletter_subscribers", force: :cascade do |t|
    t.string "email", null: false
    t.string "locale", null: false
    t.string "token", null: false
    t.string "confirmation_nonce"
    t.datetime "confirmed_at"
    t.datetime "unsubscribed_at"
    t.string "source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_shiplog_newsletter_subscribers_on_lower_email", unique: true
    t.index ["confirmation_nonce"], name: "index_shiplog_newsletter_subscribers_on_confirmation_nonce", unique: true
    t.index ["confirmed_at", "unsubscribed_at"], name: "index_shiplog_newsletter_subscribers_on_status"
    t.index ["token"], name: "index_shiplog_newsletter_subscribers_on_token", unique: true
  end

  create_table "shiplog_periods", force: :cascade do |t|
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["starts_on"], name: "index_shiplog_periods_on_starts_on", unique: true
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
    t.integer "upgrade_check_attempts", default: 0, null: false
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

  create_table "shiplog_settings", force: :cascade do |t|
    t.string "key", null: false
    t.jsonb "value", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_shiplog_settings_on_key", unique: true
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
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "shiplog_entries", "shiplog_areas", column: "area_id", on_delete: :nullify
  add_foreign_key "shiplog_entry_translations", "shiplog_entries", column: "entry_id", on_delete: :cascade
  add_foreign_key "shiplog_issues", "shiplog_repositories", column: "repository_id"
  add_foreign_key "shiplog_newsletter_deliveries", "shiplog_entries", column: "announcement_id", on_delete: :cascade
  add_foreign_key "shiplog_pull_request_upgrades", "shiplog_pull_requests", column: "pull_request_id"
  add_foreign_key "shiplog_pull_requests", "shiplog_repositories", column: "repository_id"
end
