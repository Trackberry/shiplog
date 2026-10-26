require "test_helper"

class Shiplog::Admin::InboxFiltersTest < ActionDispatch::IntegrationTest
  ADMIN = "/admin/shiplog".freeze
  FILTERED = "#{ADMIN}/?kind=change&page=2&status=draft".freeze
  QUERY = "status=draft&kind=change&page=2".freeze

  test "approve returns to the filtered list" do
    post "#{ADMIN}/entries/#{shiplog_entries(:csv_change_draft).id}/approval?#{QUERY}"
    assert_redirected_to FILTERED
  end

  test "discard returns to the filtered list" do
    post "#{ADMIN}/entries/#{shiplog_entries(:csv_change_draft).id}/discard?#{QUERY}", params: { reason: "x" }
    assert_redirected_to FILTERED
  end

  test "restore returns to the filtered list" do
    delete "#{ADMIN}/entries/#{shiplog_entries(:typo_change_discarded).id}/discard?#{QUERY}"
    assert_redirected_to FILTERED
  end

  test "update returns to the filtered list" do
    entry = shiplog_entries(:csv_change_draft)
    patch "#{ADMIN}/entries/#{entry.id}?#{QUERY}", params: { entry: { title: "New title" } }
    assert_redirected_to FILTERED
    assert_equal "New title", entry.reload.title
  end

  test "a failed update re-renders the edit page keeping the filters in the forms" do
    entry = shiplog_entries(:dark_mode_feature)
    patch "#{ADMIN}/entries/#{entry.id}?#{QUERY}", params: { entry: { released_on: "" } }
    assert_response :unprocessable_content
    assert_select "form[action=?]", "#{ADMIN}/entries/#{entry.id}?kind=change&page=2&status=draft"
  end

  test "an invalid transition and a rewrite keep the filters on the edit redirect" do
    entry = shiplog_entries(:typo_change_discarded)
    edit = "#{ADMIN}/entries/#{entry.id}/edit?kind=change&page=2&status=draft"
    post "#{ADMIN}/entries/#{entry.id}/approval?#{QUERY}"
    assert_redirected_to edit
    post "#{ADMIN}/entries/#{entry.id}/rewrite?#{QUERY}"
    assert_redirected_to edit
  end

  test "unknown or malicious values are dropped" do
    entry = shiplog_entries(:csv_change_draft)
    [
      "status=evil&kind=..%2Fx&page=-1",
      "status=evil&kind=change&page=0",
      "status[]=draft&kind=change&page=abc",
      "status=https%3A%2F%2Fevil.example%2F&kind=http%3A%2F%2Fevil.example&page=https%3A%2F%2Fevil.example",
      "return_to=https%3A%2F%2Fevil.example%2F&redirect=%2F%2Fevil.example"
    ].each do |query|
      patch "#{ADMIN}/entries/#{entry.id}?#{query}", params: { entry: { title: "T #{query.hash}" } }
      assert_response :redirect, query
      location = response.location
      assert_match(%r{\Ahttp://www\.example\.com#{ADMIN}/(\?[^#]*)?\z}, location, query)
      assert_no_match(/evil|\.\.|page=-1|page=0|page=abc/, location, query)
    end
    patch "#{ADMIN}/entries/#{entry.id}?status=evil&kind=change&page=0", params: { entry: { title: "Z" } }
    assert_redirected_to "#{ADMIN}/?kind=change"
  end

  test "the Referer is never used for the redirect" do
    entry = shiplog_entries(:csv_change_draft)
    post "#{ADMIN}/entries/#{entry.id}/approval", headers: { "Referer" => "https://evil.example/" }
    assert_redirected_to "#{ADMIN}/"
  end

  test "index buttons and edit links carry the filters" do
    get "#{ADMIN}/?status=draft&kind=change&page=1"
    q = "kind=change&amp;page=1&amp;status=draft"
    entry = shiplog_entries(:csv_change_draft)
    assert_includes response.body, "#{ADMIN}/entries/#{entry.id}/edit?#{q}"
    assert_includes response.body, "#{ADMIN}/entries/#{entry.id}/approval?#{q}"
  end

  test "index restore buttons carry the filters" do
    get "#{ADMIN}/?status=discarded&kind=change"
    entry = shiplog_entries(:typo_change_discarded)
    assert_includes response.body, "#{ADMIN}/entries/#{entry.id}/discard?kind=change&amp;status=discarded"
  end

  test "the edit page forms and links carry the filters" do
    entry = shiplog_entries(:csv_change_draft)
    q = "kind=change&page=2&status=draft"
    get "#{ADMIN}/entries/#{entry.id}/edit?#{QUERY}"
    assert_select "form[action=?]", "#{ADMIN}/entries/#{entry.id}?#{q}"
    assert_select "form[action=?]", "#{ADMIN}/entries/#{entry.id}/approval?#{q}"
    assert_select "form[action=?]", "#{ADMIN}/entries/#{entry.id}/discard?#{q}"
    assert_select "form[action=?]", "#{ADMIN}/entries/#{entry.id}/rewrite?#{q}"
    assert_select "a[href=?]", FILTERED
  end

  test "the edit page for a discarded entry carries the filters on restore" do
    entry = shiplog_entries(:typo_change_discarded)
    get "#{ADMIN}/entries/#{entry.id}/edit?status=discarded"
    assert_select "form[action=?]", "#{ADMIN}/entries/#{entry.id}/discard?status=discarded"
  end
end
