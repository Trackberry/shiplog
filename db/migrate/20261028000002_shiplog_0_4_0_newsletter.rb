# The newsletter's tables (0.4.0, second part). Additive and reversible.
class Shiplog040Newsletter < ActiveRecord::Migration[8.1]
  def change
    # --- Newsletter ---
    # Visitors who subscribed through Shiplog's form, and the addresses that unsubscribed (a suppression record,
    # also for the host's own users, who are otherwise never stored). Double opt-in: confirmation_nonce is the
    # single-use secret of the pending confirmation link, cleared when it is used; confirmed_at is set then;
    # unsubscribed_at keeps an unsubscribed address suppressed; token reaches the preferences page without an
    # account (rotated after each change there); source is the page the visitor signed up on (a consent record).
    # Unique on the lowercased email.
    create_table :shiplog_newsletter_subscribers do |t|
      t.string :email, null: false
      t.string :locale, null: false
      t.string :token, null: false
      t.string :confirmation_nonce
      t.datetime :confirmed_at
      t.datetime :unsubscribed_at
      t.string :source
      t.timestamps
    end
    add_index :shiplog_newsletter_subscribers, "lower(email)", unique: true, name: "index_shiplog_newsletter_subscribers_on_lower_email"
    add_index :shiplog_newsletter_subscribers, :token, unique: true
    add_index :shiplog_newsletter_subscribers, :confirmation_nonce, unique: true
    add_index :shiplog_newsletter_subscribers, [ :confirmed_at, :unsubscribed_at ], name: "index_shiplog_newsletter_subscribers_on_status"

    # One row per announcement and recipient ("User/42" for the host's users, "Subscriber/7" for Shiplog's
    # subscribers), inserted before the email is sent: a retried job or a second click never sends twice.
    # status is pending (claimed), sent or failed (error says why, without the address, for the admin's "Retry
    # failed"). No email address is kept here; rows older than 180 days are purged.
    create_table :shiplog_newsletter_deliveries do |t|
      t.references :announcement, null: false, foreign_key: { to_table: :shiplog_entries, on_delete: :cascade }, index: false
      t.string :recipient_key, null: false
      t.string :locale, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :sent_at
      t.text :error
      t.timestamps
    end
    add_index :shiplog_newsletter_deliveries, [ :announcement_id, :recipient_key ], unique: true, name: "index_shiplog_newsletter_deliveries_on_announcement_and_key"
    add_index :shiplog_newsletter_deliveries, [ :announcement_id, :status ], name: "index_shiplog_newsletter_deliveries_on_announcement_and_status"
    add_index :shiplog_newsletter_deliveries, :recipient_key
    add_index :shiplog_newsletter_deliveries, :created_at
  end
end
