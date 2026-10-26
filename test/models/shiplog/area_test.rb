require "test_helper"

class Shiplog::AreaTest < ActiveSupport::TestCase
  def area(name) = Shiplog::Area.create!(name:)

  test "the slug is made from the name, and the position goes last" do
    billing = area("Billing")
    shipping = area("Shipping & Tracking")

    assert_equal "billing", billing.slug
    assert_equal "shipping-tracking", shipping.slug
    assert_operator shipping.position, :>, billing.position
  end

  test "validates the name: presence, 40 characters, letters digits spaces & and -" do
    assert Shiplog::Area.new(name: "Café 2 & Co-op").valid?
    assert_not Shiplog::Area.new(name: "").valid?
    assert_not Shiplog::Area.new(name: "a" * 41).valid?
    assert Shiplog::Area.new(name: "a" * 40).valid?
    [ "<b>Bold</b>", "Quote\"s", "Semi;colon", "Emoji 🚀", "&" ].each do |name|
      assert_not Shiplog::Area.new(name:).valid?, "#{name.inspect} should be invalid"
    end
  end

  test "names are unique ignoring case, and so are slugs" do
    area("Billing")

    assert_not Shiplog::Area.new(name: "billing").valid?
    assert_not Shiplog::Area.new(name: "Billing  ").valid?
    assert_not Shiplog::Area.new(name: "Billing &").valid?, "same slug"
    assert Shiplog::Area.new(name: "Bill-ing").valid?
  end

  test "renaming updates the slug" do
    billing = area("Billing")
    billing.update!(name: "Payments & Billing")

    assert_equal "payments-billing", billing.slug
  end

  test "resolve finds by name ignoring case and spacing, then by slug" do
    shipping = area("Shipping & Tracking")

    assert_equal shipping, Shiplog::Area.resolve("shipping & tracking")
    assert_equal shipping, Shiplog::Area.resolve("  SHIPPING   &  Tracking ")
    assert_equal shipping, Shiplog::Area.resolve("shipping-tracking")
    assert_equal shipping, Shiplog::Area.resolve("Shipping Tracking")
    assert_nil Shiplog::Area.resolve("Billing")
    assert_nil Shiplog::Area.resolve("")
    assert_nil Shiplog::Area.resolve(nil)
  end

  test "resolve_or_create reuses an existing area, case-insensitively" do
    billing = area("Billing")

    assert_no_difference -> { Shiplog::Area.count } do
      assert_equal billing, Shiplog::Area.resolve_or_create("BILLING")
    end
  end

  test "resolve_or_create creates a valid new area while below max_areas" do
    Shiplog.config.max_areas = 2
    area("Billing")

    created = Shiplog::Area.resolve_or_create("Reports")
    assert_equal "Reports", created.name
    assert_predicate created, :persisted?
    assert_nil Shiplog::Area.resolve_or_create("Third"), "the cap is reached"
    assert_equal 2, Shiplog::Area.count
    assert_equal created, Shiplog::Area.resolve_or_create("reports"), "existing areas still resolve past the cap"
  end

  test "resolve_or_create returns nil for invalid names and creates nothing" do
    assert_no_difference -> { Shiplog::Area.count } do
      assert_nil Shiplog::Area.resolve_or_create("<script>alert(1)</script>")
      assert_nil Shiplog::Area.resolve_or_create("x" * 41)
      assert_nil Shiplog::Area.resolve_or_create("")
      assert_nil Shiplog::Area.resolve_or_create(nil)
      assert_nil Shiplog::Area.resolve_or_create(42)
    end
  end

  test "resolve_or_create takes the creation lock before it checks the cap" do
    Shiplog.config.max_areas = 3
    area("Billing")

    statements = sql_statements { Shiplog::Area.resolve_or_create("Reports") }

    lock = statements.index { |sql| sql.include?("pg_advisory_xact_lock") }
    assert lock, "no advisory lock was taken"
    assert(statements[lock + 1..].any? { |sql| sql.match?(/SELECT COUNT/i) }, "the cap is not checked after the lock")
  end

  test "an area created by someone else while waiting for the lock counts against the cap" do
    Shiplog.config.max_areas = 2
    area("Billing")
    raced = false
    racer = lambda do |*, payload|
      next if raced || !payload[:sql].include?("pg_advisory_xact_lock")

      raced = true # another process got the lock first, created the second area and committed
      Shiplog::Area.connection.execute("INSERT INTO shiplog_areas (name, slug, position, created_at, updated_at) VALUES ('Other', 'other', 5, NOW(), NOW())")
    end

    result = ActiveSupport::Notifications.subscribed(racer, "sql.active_record") { Shiplog::Area.resolve_or_create("Reports") }

    assert raced
    assert_nil result
    assert_equal %w[Billing Other], Shiplog::Area.order(:name).pluck(:name)
  end

  test "a non-Latin name gets a Unicode slug" do
    assert_equal "оплата", area("Оплата").slug
    assert_equal "支付", area("支付").slug
    assert_equal "оплата-и-счета", area("Оплата и Счета").slug
    assert_equal "billing", area("Billing").slug
    assert_equal "оплата", Shiplog::Area.resolve("ОПЛАТА").slug
    assert_equal "оплата", Shiplog::Area.resolve("оплата").slug
  end

  test "max_areas of 0 creates nothing" do
    Shiplog.config.max_areas = 0

    assert_nil Shiplog::Area.resolve_or_create("Billing")
  end

  test "merge_into moves the entries and deletes the source" do
    source = area("Old")
    target = area("New")
    entry = shiplog_entries(:dark_mode_feature)
    entry.update!(area: source, area_set_by_admin: true)

    source.merge_into!(target)

    assert_nil Shiplog::Area.find_by(id: source.id)
    assert_equal target, entry.reload.area
    assert entry.area_set_by_admin
  end

  test "merge_into refuses to merge an area into itself" do
    billing = area("Billing")

    assert_raises(ArgumentError) { billing.merge_into!(billing) }
    assert Shiplog::Area.exists?(billing.id)
  end

  test "merging and deleting bump the entries' updated_at" do
    source = area("Old")
    target = area("New")
    moved = shiplog_entries(:dark_mode_feature)
    moved.update_columns(area_id: source.id, updated_at: 1.year.ago)
    source.merge_into!(target)
    assert_in_delta Time.current, moved.reload.updated_at, 5

    moved.update_columns(updated_at: 1.year.ago)
    target.destroy!
    assert_in_delta Time.current, moved.reload.updated_at, 5
  end

  test "destroying an area clears its entries, including the admin flag" do
    billing = area("Billing")
    entry = shiplog_entries(:dark_mode_feature)
    entry.update!(area: billing, area_set_by_admin: true)

    billing.destroy!

    assert_nil entry.reload.area_id
    assert_not entry.area_set_by_admin
  end

  test "the database nullifies entries even when an area is deleted without callbacks" do
    billing = area("Billing")
    entry = shiplog_entries(:dark_mode_feature)
    entry.update!(area: billing)

    billing.delete

    assert_nil entry.reload.area_id
  end

  test "move shifts an area up or down the order, renumbering positions" do
    first = area("First")
    second = area("Second")
    third = area("Third")

    third.move(:up)
    assert_equal %w[First Third Second], Shiplog::Area.ordered.map(&:name)
    first.move(:down)
    assert_equal %w[Third First Second], Shiplog::Area.ordered.map(&:name)
    third.move(:up)
    assert_equal %w[Third First Second], Shiplog::Area.ordered.map(&:name), "the first area cannot go up"
    second.move(:down)
    assert_equal %w[Third First Second], Shiplog::Area.ordered.map(&:name)
    assert_equal [ 0, 1, 2 ], Shiplog::Area.ordered.map(&:position)
  end

  test "move locks all the areas in order while it renumbers" do
    area("First")
    second = area("Second")

    statements = sql_statements { second.move(:up) }

    assert(statements.any? { |sql| sql.match?(/FROM "shiplog_areas" ORDER BY .*"position".* FOR UPDATE/i) }, statements.inspect)
  end

  test "entry_counts counts every entry of each area" do
    billing = area("Billing")
    shiplog_entries(:dark_mode_feature).update!(area: billing)
    shiplog_entries(:csv_change_draft).update!(area: billing)

    assert_equal({ billing.id => 2 }, Shiplog::Area.entry_counts)
  end
end
