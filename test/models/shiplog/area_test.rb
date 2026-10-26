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

  test "entry_counts counts every entry of each area" do
    billing = area("Billing")
    shiplog_entries(:dark_mode_feature).update!(area: billing)
    shiplog_entries(:csv_change_draft).update!(area: billing)

    assert_equal({ billing.id => 2 }, Shiplog::Area.entry_counts)
  end
end
