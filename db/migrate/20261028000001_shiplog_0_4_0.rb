# Everything 0.4.0 adds to the schema, one section per feature. Additive and reversible.
class Shiplog040 < ActiveRecord::Migration[8.1]
  def change
    # --- Monthly announcements ---
    # The subject of an announcement entry: one row per month (starts_on is its first day, ends_on its last), so
    # Shiplog::Entry keeps its polymorphic subject and its unique (subject, kind) index makes drafting idempotent.
    create_table :shiplog_periods do |t|
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.timestamps
    end
    add_index :shiplog_periods, :starts_on, unique: true

    # When config.on_announcement_approved was called for the announcement's current approval: set once it is
    # approved and every configured locale has a current translation, cleared when it returns to draft, so the
    # hook runs once per approval.
    add_column :shiplog_entries, :announced_at, :datetime
  end
end
