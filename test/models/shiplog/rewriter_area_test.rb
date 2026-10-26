require "test_helper"

class Shiplog::RewriterAreaTest < ActiveSupport::TestCase
  def reply(area = :none, **extra)
    data = { title: "T", body: "B", customer_facing: true }.merge(extra)
    data[:area] = area unless area == :none
    "```json\n#{JSON.generate(data)}\n```"
  end

  def rewrite(entry, text, **options)
    Shiplog.config.rewriter = ->(_prompt) { text }
    Shiplog::Rewriter.new(entry).call(**options)
    entry.reload
  end

  def draft = shiplog_entries(:csv_change_draft)

  test "an existing area is assigned, ignoring case" do
    billing = Shiplog::Area.create!(name: "Billing")

    entry = rewrite(draft, reply("billing"))

    assert_equal billing, entry.area
    assert_equal 1, Shiplog::Area.count
  end

  test "an existing area is found by its slug" do
    shipping = Shiplog::Area.create!(name: "Shipping & Tracking")

    assert_equal shipping, rewrite(draft, reply("shipping-tracking")).area
  end

  test "a new name creates an area" do
    entry = rewrite(draft, reply("Reports"))

    assert_equal "Reports", entry.area.name
    assert_equal "reports", entry.area.slug
    assert_not entry.area_set_by_admin
  end

  test "no area is created past max_areas, and the area is nil" do
    Shiplog.config.max_areas = 1
    Shiplog::Area.create!(name: "Billing")

    entry = rewrite(draft, reply("Reports"))

    assert_nil entry.area
    assert_equal 1, Shiplog::Area.count
    assert_equal "T", entry.title, "the rewrite itself still applies"
  end

  test "an invalid name leaves the area nil and creates nothing" do
    [ "<script>alert(1)</script>", "x" * 41, "Hello, world" ].each do |name|
      assert_no_difference -> { Shiplog::Area.count } do
        assert_nil rewrite(draft, reply(name)).area
      end
    end
  end

  test "a missing area keeps today's behaviour: the entry keeps the area it had" do
    billing = Shiplog::Area.create!(name: "Billing")
    entry = draft
    entry.update!(area: billing)

    assert_equal billing, rewrite(entry, reply).area
  end

  test "an area that is not a String is ignored" do
    billing = Shiplog::Area.create!(name: "Billing")
    entry = draft
    entry.update!(area: billing)

    [ 42, [ "Billing" ], { "name" => "X" }, true, nil, "  " ].each do |value|
      result = rewrite(entry, reply(value))
      assert_equal "T", result.title, "#{value.inspect} must not fail the rewrite"
      assert_equal billing, result.area
      assert_equal 1, Shiplog::Area.count
    end
  end

  test "an unresolvable name sets the area to nil on a rewrite that had one" do
    Shiplog.config.max_areas = 1
    billing = Shiplog::Area.create!(name: "Billing")
    entry = draft
    entry.update!(area: billing)

    assert_nil rewrite(entry, reply("Reports")).area
  end

  test "unparseable replies leave the area alone and create nothing" do
    entry = rewrite(draft, "no json here, area: Billing")

    assert_nil entry.area
    assert_equal 0, Shiplog::Area.count
  end

  test "an area chosen by an admin is never changed" do
    billing = Shiplog::Area.create!(name: "Billing")
    entry = draft
    entry.update!(area: billing, area_set_by_admin: true)

    result = rewrite(entry, reply("Reports"))

    assert_equal billing, result.area
    assert_equal 1, Shiplog::Area.count, "and no area is created for it"
    assert_equal "T", result.title
  end

  test "an admin choice of no area is kept too" do
    Shiplog::Area.create!(name: "Billing")
    entry = draft
    entry.update!(area: nil, area_set_by_admin: true)

    assert_nil rewrite(entry, reply("Billing")).area
  end

  test "a forced rewrite of an approved entry with an admin-set area keeps it" do
    billing = Shiplog::Area.create!(name: "Billing")
    Shiplog::Area.create!(name: "Reports")
    entry = shiplog_entries(:dark_mode_feature)
    entry.update!(area: billing, area_set_by_admin: true)

    result = rewrite(entry, reply("Reports"), force: true)

    assert result.draft?
    assert_equal billing, result.area
  end

  test "a rewrite of an approved entry without force changes nothing" do
    Shiplog::Area.create!(name: "Billing")
    entry = shiplog_entries(:dark_mode_feature)

    assert_nil rewrite(entry, reply("Billing")).area
  end

  test "roadmap entries get areas too" do
    entry = rewrite(shiplog_entries(:soon_item_roadmap), reply("Imports"))

    assert_equal "Imports", entry.area.name
  end

  test "a discarded change creates no area" do
    entry = rewrite(draft, reply("Plumbing", customer_facing: false))

    assert entry.discarded?
    assert_nil entry.area
    assert_equal 0, Shiplog::Area.count
  end
end
