require "test_helper"

class Shiplog::Admin::EntriesControllerTest < ActionDispatch::IntegrationTest
  test "index defaults to drafts" do
    get "/admin/shiplog/"
    assert_response :ok
    assert_select "tr.shiplog-entry-row", 2
    assert_select "tr.shiplog-entry-row", text: /Better CSV validation/
    assert_select "tr.shiplog-entry-row", text: /Soon thing/
    assert_select "tr.shiplog-entry-row", text: /Dark mode/, count: 0
  end

  test "index filters by status and kind" do
    get "/admin/shiplog/", params: { status: "approved", kind: "feature" }
    assert_select "tr.shiplog-entry-row", 1
    assert_select "tr.shiplog-entry-row", text: /Dark mode/
  end

  test "index ignores unknown filter values" do
    get "/admin/shiplog/", params: { status: "bogus'; --", kind: [ "x" ] }
    assert_response :ok
    assert_select "tr.shiplog-entry-row", 2
  end

  test "index paginates 50 per page" do
    pr_repo = shiplog_repositories(:app)
    52.times do |i|
      pr = Shiplog::PullRequest.create!(repository: pr_repo, node_id: "PR_page_#{i}", number: 1000 + i, title: "PR #{i}")
      Shiplog::Entry.create!(kind: "change", subject: pr, title: "Paged #{i}")
    end
    get "/admin/shiplog/"
    assert_select "tr.shiplog-entry-row", 50
    assert_select "a.shiplog-admin-pagination__next"
    get "/admin/shiplog/", params: { page: 2 }
    assert_select "tr.shiplog-entry-row", minimum: 1
    assert_select "a.shiplog-admin-pagination__next", count: 0
  end

  test "index shows changed-source badge and rewrite error" do
    entry = shiplog_entries(:csv_change_draft)
    entry.update!(source_digest: "stale", rewrite_error: "LLM timed out")
    get "/admin/shiplog/"
    assert_select ".shiplog-badge", text: "GitHub text changed since this draft"
    assert_includes response.body, "LLM timed out"
  end

  test "index escapes titles" do
    shiplog_entries(:csv_change_draft).update!(title: "<script>alert(1)</script>")
    get "/admin/shiplog/"
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "index does not load repositories per row" do
    repository = shiplog_repositories(:app)
    add_rows = lambda do |count, offset|
      count.times do |i|
        n = 1000 + offset + i
        pr = Shiplog::PullRequest.create!(repository:, node_id: "PR_q#{n}", number: n, title: "PR #{n}", url: "https://github.com/x/y/pull/#{n}")
        issue = Shiplog::Issue.create!(repository:, node_id: "I_q#{n}", number: n, title: "Issue #{n}", url: "https://github.com/x/y/issues/#{n}")
        commit = Shiplog::Commit.create!(repository:, sha: "abc#{n}" * 6, message: "msg #{n}")
        [ pr, issue, commit ].each { |subject| Shiplog::Entry.create!(subject:, kind: "change", title: "T#{n}") }
      end
    end

    add_rows.call(2, 0)
    few = count_queries { get "/admin/shiplog/?kind=change" }
    add_rows.call(4, 10)
    many = count_queries { get "/admin/shiplog/?kind=change" }
    assert_select "tr.shiplog-entry-row", minimum: 18
    assert_equal few, many, "few=#{few} many=#{many}"
  end

  test "github links with a non-github url render as plain text" do
    entry = shiplog_entries(:csv_change_draft)
    entry.subject.update!(url: "javascript:alert(1)")
    get "/admin/shiplog/"
    assert_select "a[href^=javascript]", count: 0
    get "/admin/shiplog/entries/#{entry.id}/edit"
    assert_select "a[href^=javascript]", count: 0
    assert_select "aside", text: /Trackberry\/trackberry#14/
  end

  test "edit shows the source next to the form" do
    entry = shiplog_entries(:soon_item_roadmap)
    issue = shiplog_issues(:soon_item)
    issue.update!(body: "<b>raw</b> body")
    get "/admin/shiplog/entries/#{entry.id}/edit"
    assert_response :ok
    assert_select "form input[name='entry[title]'][value=?]", "Soon thing"
    assert_select "form textarea[name='entry[body]']", text: /Draft text\./
    assert_select "form input[name='entry[released_on]']"
    assert_includes response.body, "Soon item"
    assert_includes response.body, "&lt;b&gt;raw&lt;/b&gt; body"
    assert_select "a[href=?]", issue.url
  end

  test "edit offers regenerate with an unpublish warning for approved entries" do
    get "/admin/shiplog/entries/#{shiplog_entries(:dark_mode_feature).id}/edit"
    assert_includes response.body, "Regenerating unpublishes this entry until re-approved"
    assert_select "form[action=?] button", "/admin/shiplog/entries/#{shiplog_entries(:dark_mode_feature).id}/rewrite"
  end

  test "edit shows badges" do
    entry = shiplog_entries(:csv_change_draft)
    entry.update!(source_digest: "stale", rewrite_error: "Boom")
    get "/admin/shiplog/entries/#{entry.id}/edit"
    assert_select ".shiplog-badge", text: "GitHub text changed since this draft"
    assert_includes response.body, "Boom"
  end

  test "update saves title, body and released_on" do
    entry = shiplog_entries(:csv_change_draft)
    patch "/admin/shiplog/entries/#{entry.id}", params: { entry: { title: "New", body: "New body", released_on: "2026-10-20", status: "approved" } }
    assert_redirected_to "/admin/shiplog/"
    assert_equal "Entry saved.", flash[:notice]
    entry.reload
    assert_equal [ "New", "New body", Date.new(2026, 10, 20) ], [ entry.title, entry.body, entry.released_on ]
    assert_equal "draft", entry.status
  end

  test "update rejects a blank released_on on an approved changelog entry" do
    entry = shiplog_entries(:dark_mode_feature)
    patch "/admin/shiplog/entries/#{entry.id}", params: { entry: { title: "Dark mode", released_on: "" } }
    assert_response :unprocessable_content
    assert_equal Date.new(2026, 10, 9), entry.reload.released_on
  end

  test "unknown entry is 404" do
    get "/admin/shiplog/entries/0/edit"
    assert_response :not_found
  end
end
