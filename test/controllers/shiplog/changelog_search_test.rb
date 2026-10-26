require "test_helper"

class Shiplog::ChangelogSearchTest < ActionDispatch::IntegrationTest
  setup do
    csv = shiplog_entries(:csv_change_draft)
    csv.update!(status: "approved", released_on: Date.new(2026, 9, 15), body: "Files with unknown headers are rejected. 100% safe_mode.")
  end

  def titles = css_select(".shiplog-entry__title").map(&:text)

  def create_entries(count, title: "Export CSV")
    now = Time.current
    Shiplog::Entry.insert_all!(Array.new(count) do |i|
      { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: 20_000 + i,
        title: "#{title} #{i}", body: "Body", released_on: Date.new(2026, 8, 1), created_at: now, updated_at: now }
    end)
  end

  test "matches the title, case-insensitively" do
    get "/changelog", params: { q: "DARK" }
    assert_equal [ "Dark mode" ], titles
  end

  test "matches the body, case-insensitively" do
    get "/changelog", params: { q: "unknown HEADERS" }
    assert_equal [ "Better CSV validation" ], titles
  end

  test "every word must match the title or the body" do
    get "/changelog", params: { q: "csv headers" }
    assert_equal [ "Better CSV validation" ], titles
    get "/changelog", params: { q: "csv theme" }
    assert_empty titles
    get "/changelog", params: { q: "dark headers" }
    assert_empty titles
  end

  test "caps the query at five words and 100 characters" do
    get "/changelog", params: { q: "better csv validation files with nonexistent" }
    assert_equal [ "Better CSV validation" ], titles
    get "/changelog", params: { q: "#{"a" * 99} validation" }
    assert_empty titles
    get "/changelog", params: { q: "#{"b" * 97} dark mode" }
    assert_select ".shiplog-search__summary", text: /#{"b" * 97} da”/
    assert_select ".shiplog-search__summary", text: /dark/, count: 0
  end

  test "escapes LIKE wildcards" do
    get "/changelog", params: { q: "%" }
    assert_equal [ "Better CSV validation" ], titles # only the body with a literal percent sign
    get "/changelog", params: { q: "_" }
    assert_equal [ "Better CSV validation" ], titles # safe_mode
    get "/changelog", params: { q: "d_rk" }
    assert_empty titles
    get "/changelog", params: { q: "\\" }
    assert_empty titles
  end

  test "excludes drafts, discarded and roadmap entries" do
    shiplog_entries(:csv_change_draft).update!(status: "draft")
    get "/changelog", params: { q: "csv" }
    assert_empty titles
    get "/changelog", params: { q: "upload" }
    assert_empty titles
    get "/changelog", params: { q: "typo" }
    assert_empty titles
  end

  test "results stay grouped by month, newest first" do
    shiplog_entries(:dark_mode_feature).update!(body: "Also CSV export")
    get "/changelog", params: { q: "csv" }
    assert_equal [ "October 2026", "September 2026" ], css_select("h2.shiplog-month__title").map(&:text)
  end

  test "the form keeps the query and is accessible" do
    get "/changelog", params: { q: "dark" }
    assert_select "form.shiplog-search[role=search][method=get][action=?]", "/changelog" do
      assert_select "input.shiplog-search__input[type=search][name=q][value=dark][placeholder=?]", "Search the changelog"
      assert_select "input.shiplog-search__input[aria-label=?]", "Search the changelog"
      assert_select "button.shiplog-search__button[type=submit]", text: "Search"
    end
  end

  test "the form renders without a query and no summary" do
    get "/changelog"
    assert_select "form.shiplog-search input[name=q]"
    assert_select ".shiplog-search__summary", 0
  end

  test "the summary counts the results and links back" do
    get "/changelog", params: { q: "csv" }
    assert_select ".shiplog-search__summary", text: /1 result for “csv”/
    assert_select ".shiplog-search__summary a.shiplog-search__clear[href=?]", "/changelog", text: "Clear search"
    shiplog_entries(:dark_mode_feature).update!(body: "CSV too")
    get "/changelog", params: { q: "csv" }
    assert_select ".shiplog-search__summary", text: /2 results for “csv”/
  end

  test "the summary escapes the query" do
    get "/changelog", params: { q: "<script>x</script>" }
    assert_not_includes response.body, "<script>x</script>"
  end

  test "no results shows its own message, not the empty changelog text" do
    get "/changelog", params: { q: "zzz" }
    assert_response :ok
    assert_select "p.shiplog-search__empty", text: /No entries match “zzz”/
    assert_select "p.shiplog-empty", 0
    assert_select ".shiplog-search__summary", text: /0 results for “zzz”/
  end

  test "page beyond the results is not found" do
    get "/changelog", params: { q: "zzz", page: 2 }
    assert_response :not_found
  end

  test "pagination links keep the query" do
    create_entries(31)
    get "/changelog", params: { q: "export" }
    assert_select ".shiplog-entry", 30
    assert_select "a.shiplog-pagination__link--older[href=?]", "/changelog?page=2&q=export"
    get "/changelog", params: { q: "export", page: 2 }
    assert_select "a.shiplog-pagination__link--newer[href=?]", "/changelog?q=export"
  end

  test "a blank query is the same as none" do
    get "/changelog"
    plain = response.body
    plain_etag = response.headers["ETag"]
    [ "", "   ", " \t " ].each do |blank|
      get "/changelog", params: { q: blank }
      assert_equal plain.gsub(/value=""/, ""), response.body.gsub(/value=""/, "")
      assert_equal plain_etag, response.headers["ETag"]
    end
    assert_select ".shiplog-search__summary", 0
  end

  test "the count query only runs with a query" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/COUNT/i) && payload[:sql].include?("shiplog_entries") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/changelog"
      assert_empty queries
      get "/changelog", params: { q: "csv" }
    end
    assert_equal 1, queries.size
  end

  test "ETag includes the normalised query" do
    get "/changelog", params: { q: "csv" }
    csv = response.headers["ETag"]
    get "/changelog", params: { q: "  CSV  " }
    assert_not_equal csv, response.headers["ETag"] # case matters for display
    get "/changelog", params: { q: " csv " }
    assert_equal csv, response.headers["ETag"]
    get "/changelog", params: { q: "dark" }
    assert_not_equal csv, response.headers["ETag"]
    get "/changelog", params: { q: "csv" }, headers: { "If-None-Match" => csv }
    assert_response :not_modified
  end

  test "changelog_search false hides the form and ignores q" do
    Shiplog.config.changelog_search = false
    get "/changelog", params: { q: "dark" }
    assert_select "form.shiplog-search", 0
    assert_select ".shiplog-search__summary", 0
    assert_equal [ "Dark mode", "Better CSV validation" ].sort, titles.sort
    assert_select "meta[name=robots]", 0
  end

  test "pagination does not carry q when search is off" do
    Shiplog.config.changelog_search = false
    create_entries(31)
    get "/changelog", params: { q: "export" }
    assert_select "a.shiplog-pagination__link--older[href=?]", "/changelog?page=2"
  end

  test "ETag changes with changelog_search" do
    get "/changelog"
    etag = response.headers["ETag"]
    Shiplog.config.changelog_search = false
    get "/changelog"
    assert_not_equal etag, response.headers["ETag"]
  end

  test "config.classes apply to the search elements" do
    Shiplog.config.classes = { search: "s", search_input: "si", search_button: "sb", search_summary: "ss", search_clear: "sc", search_empty: "se" }
    get "/changelog", params: { q: "csv" }
    assert_select "form.shiplog-search.s input.shiplog-search__input.si"
    assert_select "button.shiplog-search__button.sb"
    assert_select "p.shiplog-search__summary.ss a.shiplog-search__clear.sc"
    get "/changelog", params: { q: "zzz" }
    assert_select "p.shiplog-search__empty.se"
  end

  test "search pages ask not to be indexed, the plain changelog does not" do
    get "/changelog", params: { q: "csv" }
    assert_select "head meta[name=robots][content=noindex]", 1
    get "/changelog"
    assert_select "meta[name=robots]", 0
  end

  test "a host layout can read content_for shiplog_robots" do
    Shiplog.config.public_layout = "custom"
    get "/changelog", params: { q: "csv" }
    assert_select "#host-robots[data-content=noindex]"
  end

  # Other keys (title, categories) have no defaults in 0.2.0 and are not this feature's concern.
  test "renders under a locale without translations, in English" do
    I18n.backend.eager_load!
    with_extra_locale(:fr) do
      I18n.backend.store_translations(:fr, date: { month_names: [ nil ] + %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre] })
      get "/changelog", params: { q: "csv" }
      assert_response :ok
      assert_no_match(/translation missing: fr\.shiplog\.changelog\.search/i, response.body)
      assert_select ".shiplog-search__summary", text: /1 result for “csv”/
      assert_select "button.shiplog-search__button", text: "Search"
      get "/changelog", params: { q: "zzz" }
      assert_no_match(/translation missing: fr\.shiplog\.changelog\.search/i, response.body)
      assert_select ".shiplog-search__empty", text: /No entries match/
    end
  end
end
