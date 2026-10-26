require "test_helper"

class Shiplog::DetectAreasJobTest < ActiveJob::TestCase
  test "runs the area detection" do
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: "e" * 40, message: "m", committed_at: Time.current, url: "https://x/1")
    entry = Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title: "Invoices emailed", body: "B", released_on: Date.new(2026, 10, 1), approved_at: Time.current)
    Shiplog.config.rewriter = lambda do |prompt|
      prompt.include?(%("areas")) ? %({"areas": ["Billing"]}) : %({"assignments": [{"id": #{entry.id}, "area": "Billing"}]})
    end

    Shiplog::DetectAreasJob.perform_now

    assert_equal "Billing", entry.reload.area.name
  end

  test "with recheck: true it asks again about entries it had declined" do
    Shiplog::Area.create!(name: "Billing")
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: "d" * 40, message: "m", committed_at: Time.current, url: "https://x/2")
    entry = Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title: "Invoices emailed", body: "B", released_on: Date.new(2026, 10, 1),
      approved_at: Time.current, area_detected_at: 1.day.ago)
    Shiplog.config.rewriter = ->(_prompt) { %({"assignments": [{"id": #{entry.id}, "area": "Billing"}]}) }

    Shiplog::DetectAreasJob.perform_now
    assert_nil entry.reload.area
    Shiplog::DetectAreasJob.perform_now(recheck: true)

    assert_equal "Billing", entry.reload.area.name
  end

  test "can be enqueued" do
    assert_enqueued_with(job: Shiplog::DetectAreasJob) { Shiplog::DetectAreasJob.perform_later }
  end
end
