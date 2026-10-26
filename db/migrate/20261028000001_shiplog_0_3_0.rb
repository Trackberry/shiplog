# Everything 0.3.0 adds to the schema, one section per feature. Additive and reversible.
class Shiplog030 < ActiveRecord::Migration[8.1]
  def change
    # --- Entry permalinks (/changelog/:slug) ---
    # Set when an entry is first approved, never changed afterwards, so links never break. Nil for roadmap
    # entries and drafts. `rake shiplog:backfill_slugs` fills it for entries approved before 0.3.0.
    add_column :shiplog_entries, :slug, :string
    add_index :shiplog_entries, :slug, unique: true, where: "slug IS NOT NULL"

    # --- "What's new" unseen count ---
    # `Shiplog.unseen_count` counts approved feature and change entries with `approved_at > since`:
    # an equality column first, then the range column.
    add_index :shiplog_entries, [ :status, :approved_at ]
  end
end
