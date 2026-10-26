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

  test "records the last run for the Areas page" do
    Shiplog::Area.create!(name: "Billing")
    Shiplog.config.rewriter = ->(_prompt) { %({"assignments": []}) }

    Shiplog::DetectAreasJob.perform_now

    last = Shiplog::Setting.read("area_detection")
    assert_equal 0, last["assigned"]
    assert_nil last["error"]
    assert_in_delta Time.current, Time.zone.parse(last["at"]), 5
  end

  test "a failure is logged, recorded and never retried or raised" do
    Shiplog::Area.create!(name: "Billing")
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: "f" * 40, message: "m", committed_at: Time.current, url: "https://x/3")
    Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title: "Invoices emailed", body: "B", released_on: Date.new(2026, 10, 1), approved_at: Time.current)
    Shiplog.config.rewriter = ->(_prompt) { raise ArgumentError, "model down" }
    output = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output)

    assert_no_enqueued_jobs { Shiplog::DetectAreasJob.perform_now }

    logged = output.string
    assert_match(/\[shiplog\] Detect areas failed: ArgumentError: model down/, logged)
    assert_operator logged.lines.count { |line| line.include?("detect_areas_job_test.rb") || line.include?("area_detector.rb") }, :<=, 5
    last = Shiplog::Setting.read("area_detection")
    assert_equal "ArgumentError: model down", last["error"]
  ensure
    Rails.logger = original
  end

  test "can be enqueued" do
    assert_enqueued_with(job: Shiplog::DetectAreasJob) { Shiplog::DetectAreasJob.perform_later }
  end
end
