require "test_helper"

class Shiplog::AnnouncementAreaDetectionTest < ActiveSupport::TestCase
  test "the area detector never sends an announcement to the AI nor gives it an area" do
    announcement = Shiplog::Announcements.draft(month: Date.new(2026, 10, 1))
    announcement.approve!(by: "ed@example.com")
    Shiplog::Entry.where.not(id: announcement.id).delete_all
    Shiplog::Area.create!(name: "Billing")
    prompts = []
    Shiplog.config.rewriter = lambda do |prompt|
      prompts << prompt
      JSON.generate(assignments: [ { id: announcement.id, area: "Billing" } ])
    end

    assigned = Shiplog::AreaDetector.new.call

    assert_equal 0, assigned
    assert_empty prompts
    assert_nil announcement.reload.area_id
    assert_nil announcement.area_detected_at
  end
end
