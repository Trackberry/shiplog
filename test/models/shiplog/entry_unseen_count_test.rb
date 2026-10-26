require "test_helper"

class Shiplog::EntryUnseenCountTest < ActiveSupport::TestCase
  def approved(kind, approved_at, n)
    Shiplog::Entry.insert_all!([ { kind:, status: "approved", subject_type: "Shiplog::Issue", subject_id: 50_000 + n,
      title: "Unseen #{n}", body: "Body", released_on: Date.new(2026, 10, 1), approved_at:, created_at: Time.current, updated_at: Time.current } ])
  end

  test "a nil since counts every approved feature and change" do
    assert_equal 1, Shiplog.unseen_count(since: nil)
    assert_equal 1, Shiplog.unseen_count
  end

  test "since counts entries approved strictly after it" do
    approved("change", Time.zone.local(2026, 10, 20), 1)
    assert_equal 2, Shiplog.unseen_count(since: Time.zone.local(2026, 10, 1))
    assert_equal 1, Shiplog.unseen_count(since: Time.zone.local(2026, 10, 15))
    assert_equal 0, Shiplog.unseen_count(since: Time.zone.local(2026, 10, 20))
  end

  test "only approved features and changes count" do
    approved("roadmap", Time.zone.local(2026, 10, 20), 1)
    assert_equal 1, Shiplog.unseen_count(since: nil)
    shiplog_entries(:csv_change_draft).update_columns(approved_at: Time.zone.local(2026, 10, 20))
    shiplog_entries(:typo_change_discarded).update_columns(approved_at: Time.zone.local(2026, 10, 20))
    assert_equal 1, Shiplog.unseen_count(since: nil)
  end

  test "the count is capped at 99" do
    Shiplog::Entry.insert_all!(Array.new(120) do |i|
      { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: 60_000 + i, title: "Bulk #{i}", body: "B",
        released_on: Date.new(2026, 10, 1), approved_at: Time.zone.local(2026, 10, 20), created_at: Time.current, updated_at: Time.current }
    end)
    assert_equal 99, Shiplog.unseen_count(since: nil)
    assert_equal 99, Shiplog.unseen_count(since: Time.zone.local(2026, 10, 1))
  end

  test "the view helper returns the same count" do
    helper = Class.new { include Shiplog::UnseenHelper }.new
    assert_equal 1, helper.shiplog_unseen_count(nil)
    assert_equal 0, helper.shiplog_unseen_count(Time.zone.local(2026, 11, 1))
  end

  test "it is one query" do
    assert_equal 1, count_queries { Shiplog.unseen_count(since: Time.zone.local(2026, 10, 1)) }
  end
end
