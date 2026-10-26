class CreateShiplogPullRequestUpgrades < ActiveRecord::Migration[8.1]
  def change
    # What upgrade detection needs from the pull request, and its "checked" marker: a pull request with
    # no tracked upgrade has no upgrade row, so only a column can say "inspected, nothing found".
    change_table :shiplog_pull_requests do |t|
      t.string :base_oid
      t.string :merge_oid
      t.boolean :lockfile_changed, null: false, default: false
      t.datetime :upgrades_checked_at
    end

    create_table :shiplog_pull_request_upgrades do |t|
      t.references :pull_request, null: false, foreign_key: { to_table: :shiplog_pull_requests }, index: false
      t.string :gem_name, null: false
      t.string :from_ref
      t.string :to_ref
      t.string :gem_repository
      # Not `changes`: that name belongs to ActiveModel::Dirty and Active Record refuses it as an attribute.
      t.jsonb :gem_changes, null: false, default: []
      t.timestamps
      t.index [ :pull_request_id, :gem_name ], unique: true
    end
  end
end
