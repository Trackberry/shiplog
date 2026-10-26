require "test_helper"

class Shiplog::ChangelogsControllerTest < ActionDispatch::IntegrationTest
  def create_entries(count, kind: "change", released_on: Date.new(2026, 9, 1), offset: 10_000)
    now = Time.current
    rows = Array.new(count) do |i|
      { kind:, status: "approved", subject_type: "Shiplog::Issue", subject_id: offset + i,
        title: "Bulk #{kind} #{offset + i}", body: "Body", released_on:, created_at: now, updated_at: now }
    end
    Shiplog::Entry.insert_all!(rows)
  end

  test "lists approved features grouped by month heading" do
    shiplog_entries(:csv_change_draft).approve!(by: "ed@example.com")
    shiplog_entries(:csv_change_draft).update!(released_on: Date.new(2026, 9, 15))
    get "/changelog"
    assert_response :ok
    assert_select "h2.shiplog-month__title", text: "October 2026"
    assert_select "h2.shiplog-month__title", text: "September 2026"
    assert_select ".shiplog-entry__title", text: "Dark mode"
    assert_select ".shiplog-entry__title", text: "Better CSV validation"
  end

  test "months are newest first" do
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 9, 15))
    get "/changelog"
    titles = css_select("h2.shiplog-month__title").map(&:text)
    assert_equal [ "October 2026", "September 2026" ], titles
  end

  test "excludes drafts, discarded and roadmap entries" do
    get "/changelog"
    assert_not_includes response.body, "Better CSV validation"
    assert_not_includes response.body, "Typo fix"
    assert_not_includes response.body, "Upload many shipments at once"
  end

  test "feature entries are marked" do
    shiplog_entries(:csv_change_draft).update!(status: "approved", released_on: Date.new(2026, 10, 1))
    get "/changelog"
    assert_select "li.shiplog-entry--feature", 1
    assert_select "li.shiplog-entry--feature .shiplog-entry__title", text: "Dark mode"
    assert_select "li.shiplog-entry--change", 1
  end

  test "escapes HTML in bodies" do
    shiplog_entries(:dark_mode_feature).update!(body: "<b>bold</b>")
    get "/changelog"
    assert_not_includes response.body, "<b>bold</b>"
    assert_includes response.body, "&lt;b&gt;bold&lt;/b&gt;"
  end

  test "never leaks GitHub details" do
    get "/changelog"
    assert_not_includes response.body, "github.com"
  end

  test "empty state" do
    Shiplog::Entry.update_all(status: "draft")
    get "/changelog"
    assert_select ".shiplog-empty", text: "Nothing here yet"
  end

  test "paginates 30 per page with older and newer links" do
    create_entries(60)
    get "/changelog"
    assert_select ".shiplog-entry", 30
    assert_select "a.shiplog-pagination__older[href=?]", "/changelog?page=2"
    assert_select "a.shiplog-pagination__newer", 0

    get "/changelog", params: { page: 2 }
    assert_select ".shiplog-entry", 30
    assert_select "a.shiplog-pagination__newer[href=?]", "/changelog"
    assert_select "a.shiplog-pagination__older[href=?]", "/changelog?page=3"

    get "/changelog", params: { page: 3 }
    assert_select ".shiplog-entry", 1
    assert_select "a.shiplog-pagination__older", 0
  end

  test "page param is clamped and non-numeric means page one" do
    get "/changelog", params: { page: "-4" }
    assert_response :ok
    assert_select ".shiplog-entry__title", text: "Dark mode"
    get "/changelog", params: { page: "abc" }
    assert_select ".shiplog-entry__title", text: "Dark mode"
    get "/changelog", params: { page: "0" }
    assert_select ".shiplog-entry__title", text: "Dark mode"
    get "/changelog", params: { page: { a: 1 } }
    assert_response :ok
    get "/changelog", params: { page: "9" * 40 }
    assert_response :ok
  end

  test "respects the configured public layout" do
    Shiplog.config.public_layout = "custom"
    get "/changelog"
    assert_select "#host-layout-marker"
  end
end
