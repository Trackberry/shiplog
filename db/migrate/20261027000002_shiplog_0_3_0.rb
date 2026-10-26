# Everything 0.3.0 adds to the schema, one section per feature. Additive and reversible.
class Shiplog030 < ActiveRecord::Migration[8.1]
  # A migration must not depend on model code that changes later: this is a bare table-backed class.
  class MigrationEntry < ActiveRecord::Base
    self.table_name = "shiplog_entries"
    self.inheritance_column = nil
  end

  SLUG_MAX_LENGTH = 80

  def change
    # --- Entry permalinks (/changelog/:slug) ---
    # Set when an entry is first approved, never changed afterwards, so links never break. Nil for roadmap
    # entries and drafts. Entries approved before 0.3.0 get theirs here (oldest first, so the oldest keeps the
    # plain slug on duplicate titles): the public pages never write, so nothing else fills them in.
    add_column :shiplog_entries, :slug, :string
    add_index :shiplog_entries, :slug, unique: true, where: "slug IS NOT NULL"
    reversible do |direction|
      direction.up do
        MigrationEntry.reset_column_information
        backfill_slugs
      end
    end

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

  # Gives every approved feature and change with a release date, and no slug, one: the title as [a-z0-9-] only
  # (cut at 80 characters), made unique with -2, -3, ...; entry-<id> when nothing is left. The same rules as
  # Shiplog::Entry#generate_slug at the time of 0.3.0.
  def backfill_slugs
    taken = MigrationEntry.where.not(slug: nil).pluck(:slug).to_set
    MigrationEntry.where(status: "approved", kind: %w[feature change], slug: nil).where.not(released_on: nil)
      .order(:released_on, :approved_at, :id).to_a.each do |entry|
      slug = slug_for(entry, taken)
      taken << slug
      MigrationEntry.where(id: entry.id, slug: nil).update_all(slug:)
    end
  end

  private

  def slug_for(entry, taken)
    base = entry.title.to_s.parameterize.tr("_", "-").squeeze("-").first(SLUG_MAX_LENGTH).gsub(/\A-+|-+\z/, "").presence || "entry-#{entry.id}"
    candidate = base
    suffix = 2
    while taken.include?(candidate)
      tail = "-#{suffix}"
      candidate = "#{base.first(SLUG_MAX_LENGTH - tail.length).delete_suffix("-")}#{tail}"
      suffix += 1
    end
    candidate
  end
end
