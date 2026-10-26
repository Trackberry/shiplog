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

    # --- Product areas (detected by AI) ---
    # `entries.area_id` is nullable; deleting an area nullifies it (merging moves the entries first).
    # `area_set_by_admin` marks an area chosen by hand, which detection never overwrites.
    create_table :shiplog_areas do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :shiplog_areas, :slug, unique: true
    add_reference :shiplog_entries, :area, null: true, index: true, foreign_key: { to_table: :shiplog_areas, on_delete: :nullify }
    add_column :shiplog_entries, :area_set_by_admin, :boolean, null: false, default: false
  end
end
