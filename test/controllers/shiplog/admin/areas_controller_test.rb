require "test_helper"

class Shiplog::Admin::AreasControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  ADMIN = "/admin/shiplog".freeze

  setup do
    @billing = Shiplog::Area.create!(name: "Billing")
    @reports = Shiplog::Area.create!(name: "Reports")
    @empty = Shiplog::Area.create!(name: "Empty")
    shiplog_entries(:dark_mode_feature).update!(area: @billing)
    shiplog_entries(:csv_change_draft).update!(area: @billing)
    shiplog_entries(:typo_change_discarded).update!(area: @reports)
  end

  test "the admin nav links to the Areas page" do
    get "#{ADMIN}/"
    assert_select "nav.shiplog-admin-nav a[href=?]", "#{ADMIN}/areas", text: "Areas"
  end

  test "lists the areas in order with their entry counts" do
    get "#{ADMIN}/areas"

    assert_response :ok
    assert_select "tr.shiplog-area-row", 3
    rows = css_select("tr.shiplog-area-row")
    assert_equal "Billing", rows[0].at_css("input[name='area[name]']")["value"]
    assert_equal "2", rows[0].at_css(".shiplog-area-row__count").text.strip
    assert_equal "1", rows[1].at_css(".shiplog-area-row__count").text.strip
    assert_equal "0", rows[2].at_css(".shiplog-area-row__count").text.strip
    assert_select "tr.shiplog-area-row input[name='area[name]'][value=?]", "Billing"
  end

  test "shows an empty state and the detect button when there are no areas" do
    Shiplog::Area.destroy_all
    get "#{ADMIN}/areas"

    assert_select "tr.shiplog-area-row", 0
    assert_select ".shiplog-admin__empty"
    assert_select "form[action=?] button", "#{ADMIN}/areas/detection", text: "Detect areas"
  end

  test "the detect button enqueues the job and flashes" do
    assert_enqueued_with(job: Shiplog::DetectAreasJob) do
      post "#{ADMIN}/areas/detection"
    end
    assert_redirected_to "#{ADMIN}/areas"
    follow_redirect!
    assert_select ".shiplog-admin__flash--notice", text: "Detection queued. Refresh in a moment."
  end

  test "the detect form offers a re-check of unplaced entries" do
    get "#{ADMIN}/areas"

    assert_select "form[action=?]", "#{ADMIN}/areas/detection" do
      assert_select "input[type=checkbox][name=recheck][value='1']"
      assert_select "label", text: "Re-check unplaced entries"
    end
  end

  test "detect enqueues with recheck only when asked" do
    assert_enqueued_with(job: Shiplog::DetectAreasJob, args: [ { recheck: false } ]) { post "#{ADMIN}/areas/detection" }
    assert_enqueued_with(job: Shiplog::DetectAreasJob, args: [ { recheck: true } ]) { post "#{ADMIN}/areas/detection", params: { recheck: "1" } }
  end

  test "rename updates the name and the slug" do
    patch "#{ADMIN}/areas/#{@billing.id}", params: { area: { name: "Payments & Billing" } }

    assert_redirected_to "#{ADMIN}/areas"
    assert_equal "Payments & Billing", @billing.reload.name
    assert_equal "payments-billing", @billing.slug
  end

  test "rename rejects invalid and duplicate names" do
    patch "#{ADMIN}/areas/#{@billing.id}", params: { area: { name: "<b>x</b>" } }
    assert_redirected_to "#{ADMIN}/areas"
    assert_equal "Billing", @billing.reload.name
    follow_redirect!
    assert_select ".shiplog-admin__flash--alert"

    patch "#{ADMIN}/areas/#{@billing.id}", params: { area: { name: "reports" } }
    assert_equal "Billing", @billing.reload.name
  end

  test "rename ignores other attributes" do
    patch "#{ADMIN}/areas/#{@billing.id}", params: { area: { name: "Billing", slug: "evil", position: 9 } }

    assert_equal "billing", @billing.reload.slug
  end

  test "move up and down reorder" do
    post "#{ADMIN}/areas/#{@reports.id}/move", params: { direction: "up" }
    assert_redirected_to "#{ADMIN}/areas"
    assert_equal %w[Reports Billing Empty], Shiplog::Area.ordered.map(&:name)

    post "#{ADMIN}/areas/#{@reports.id}/move", params: { direction: "down" }
    assert_equal %w[Billing Reports Empty], Shiplog::Area.ordered.map(&:name)

    post "#{ADMIN}/areas/#{@reports.id}/move", params: { direction: "sideways" }
    assert_equal %w[Billing Reports Empty], Shiplog::Area.ordered.map(&:name)
  end

  test "merge moves the entries to the target and deletes the source" do
    post "#{ADMIN}/areas/#{@billing.id}/merge", params: { target_id: @reports.id }

    assert_redirected_to "#{ADMIN}/areas"
    assert_nil Shiplog::Area.find_by(id: @billing.id)
    assert_equal 3, @reports.entries.count
  end

  test "merge into itself or a missing area changes nothing" do
    post "#{ADMIN}/areas/#{@billing.id}/merge", params: { target_id: @billing.id }
    assert_redirected_to "#{ADMIN}/areas"
    post "#{ADMIN}/areas/#{@billing.id}/merge", params: { target_id: 0 }
    post "#{ADMIN}/areas/#{@billing.id}/merge"

    assert Shiplog::Area.exists?(@billing.id)
    assert_equal 2, @billing.entries.count
  end

  test "delete removes the area and clears its entries" do
    delete "#{ADMIN}/areas/#{@billing.id}"

    assert_redirected_to "#{ADMIN}/areas"
    assert_nil Shiplog::Area.find_by(id: @billing.id)
    assert_nil shiplog_entries(:dark_mode_feature).reload.area_id
    assert_equal 2, Shiplog::Area.count
  end

  test "an unknown area answers 404" do
    patch "#{ADMIN}/areas/0", params: { area: { name: "X" } }
    assert_response :not_found
  end

  test "the edit page has an area select with None, and the current area selected" do
    entry = shiplog_entries(:dark_mode_feature)
    entry.update!(area: @reports)
    get "#{ADMIN}/entries/#{entry.id}/edit"

    assert_select "select[name='entry[area_id]']" do
      assert_select "option[value='']", text: "None"
      assert_select "option", 4
      assert_select "option[selected][value=?]", @reports.id.to_s, text: "Reports"
    end
  end

  test "saving a different area sets area_set_by_admin" do
    entry = shiplog_entries(:dark_mode_feature)
    patch "#{ADMIN}/entries/#{entry.id}", params: { entry: { title: entry.title, area_id: @reports.id } }

    assert_equal @reports, entry.reload.area
    assert entry.area_set_by_admin
  end

  test "choosing None clears the area and keeps it cleared" do
    entry = shiplog_entries(:dark_mode_feature)
    entry.update!(area: @billing)
    patch "#{ADMIN}/entries/#{entry.id}", params: { entry: { title: entry.title, area_id: "" } }

    assert_nil entry.reload.area
    assert entry.area_set_by_admin
  end

  test "saving without touching the area does not lock it" do
    entry = shiplog_entries(:dark_mode_feature)
    entry.update!(area: @billing)
    patch "#{ADMIN}/entries/#{entry.id}", params: { entry: { title: "New title", area_id: @billing.id } }

    assert_equal "New title", entry.reload.title
    assert_not entry.area_set_by_admin
  end

  test "an unknown area id is rejected" do
    entry = shiplog_entries(:dark_mode_feature)
    patch "#{ADMIN}/entries/#{entry.id}", params: { entry: { title: "x", area_id: 999_999 } }

    assert_response :unprocessable_content
    assert_equal @billing, entry.reload.area
  end

  test "the inbox shows the area as a badge, and nothing for entries without one" do
    get "#{ADMIN}/?status=approved"
    assert_select "tr.shiplog-entry-row .shiplog-badge--area", text: "Billing"

    get "#{ADMIN}/"
    assert_select "tr.shiplog-entry-row .shiplog-badge--area", count: 1, text: "Billing"
    assert_select "tr.shiplog-entry-row", text: /Soon thing/ do |rows|
      assert_select rows.first, ".shiplog-badge--area", 0
    end
  end

  test "the inbox does not load areas per row" do
    shiplog_entries(:soon_item_roadmap).update!(area: @reports)
    few = count_queries { get "#{ADMIN}/?status=approved" }
    Shiplog::Entry.where.not(area_id: nil).update_all(area_id: @empty.id)
    same = count_queries { get "#{ADMIN}/?status=approved" }

    assert_equal few, same
  end

  test "the inline row response carries the badge, and the filters stay on the edit save" do
    entry = shiplog_entries(:csv_change_draft)
    post "#{ADMIN}/entries/#{entry.id}/discard?status=draft", params: { reason: "x" }, headers: { "Accept" => "application/json" }
    assert_includes response.parsed_body["row"], "shiplog-badge--area"

    patch "#{ADMIN}/entries/#{entry.id}?status=discarded&kind=change", params: { entry: { area_id: @reports.id } }
    assert_redirected_to "#{ADMIN}/?kind=change&status=discarded"
  end

  test "the new admin strings fall back to English defaults under a locale without translations" do
    I18n.backend.eager_load!
    new_keys = /translation missing: fr\.shiplog\.admin\.(areas|nav\.areas|entries\.(no_area|fields\.area))/i
    with_extra_locale(:fr) do
      get "#{ADMIN}/areas"
      assert_response :ok
      assert_no_match(new_keys, response.body)
      assert_select "form[action=?] button", "#{ADMIN}/areas/detection", text: "Detect areas"
      assert_select "a", text: "Areas"
      get "#{ADMIN}/entries/#{shiplog_entries(:dark_mode_feature).id}/edit"
      assert_no_match(new_keys, response.body)
      assert_select "option[value='']", text: "None"
      post "#{ADMIN}/areas/detection"
      follow_redirect!
      assert_select ".shiplog-admin__flash--notice", text: "Detection queued. Refresh in a moment."
    end
  end
end
