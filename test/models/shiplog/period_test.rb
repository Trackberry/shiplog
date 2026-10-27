require "test_helper"

class Shiplog::PeriodTest < ActiveSupport::TestCase
  OCTOBER = Date.new(2026, 10, 1)

  def commit_subject(title = "c")
    Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: title,
      committed_at: Time.current, url: "https://example.com/commit/1")
  end

  def change(title, released_on, status: "approved", area: nil, body: "It works better. More text here.", slug: nil, **attributes)
    Shiplog::Entry.create!(kind: "change", status:, subject: commit_subject(title), title:, body:, released_on:, area:,
      approved_at: (Time.current if status == "approved"), slug: slug || (title.parameterize if status == "approved"), **attributes)
  end

  def period = Shiplog::Period.month(OCTOBER)

  test "month creates the period once, from the first to the last day of the month" do
    first = Shiplog::Period.month(Date.new(2026, 10, 17))
    second = Shiplog::Period.month(OCTOBER)

    assert_equal first, second
    assert_equal 1, Shiplog::Period.count
    assert_equal Date.new(2026, 10, 1), first.starts_on
    assert_equal Date.new(2026, 10, 31), first.ends_on
  end

  test "changelog_entries lists approved features first, then changes, within the month only" do
    older = change("Alpha change", Date.new(2026, 10, 2))
    newer = change("Beta change", Date.new(2026, 10, 20))
    change("September change", Date.new(2026, 9, 30))
    change("November change", Date.new(2026, 11, 1))
    change("Draft change", Date.new(2026, 10, 5), status: "draft")
    change("Discarded change", Date.new(2026, 10, 6), status: "discarded")

    assert_equal [ shiplog_entries(:dark_mode_feature), older, newer ], period.changelog_entries.to_a
  end

  test "title is the month and year" do
    assert_equal "October 2026", period.title
  end

  test "title falls back to the English month name when the locale lacks month names" do
    default = I18n.default_locale
    with_extra_locale(:xx) do
      I18n.default_locale = :xx
      assert_equal "October 2026", period.title
    ensure
      I18n.default_locale = default
    end
  end

  test "body lists the features under New with a link, then the changes under Also improved by area" do
    billing = Shiplog::Area.create!(name: "Billing")
    reports = Shiplog::Area.create!(name: "Reports")
    change("Invoice export", Date.new(2026, 10, 3), area: billing, body: "Export invoices as PDF. Second sentence.")
    change("Report filters", Date.new(2026, 10, 4), area: reports)
    change("Loose change", Date.new(2026, 10, 5))

    body = period.body

    assert_includes body, "## New\n\n- [Dark mode](/changelog/dark-mode): Switch to a dark theme."
    assert_includes body, "## Also improved"
    assert_includes body, "### Billing\n\n- [Invoice export](/changelog/invoice-export): Export invoices as PDF."
    assert_includes body, "### Reports\n\n- [Report filters](/changelog/report-filters)"
    assert_operator body.index("- [Loose change]"), :<, body.index("### Billing")
    assert_operator body.index("### Billing"), :<, body.index("### Reports")
    assert_not_includes body, "Second sentence"
    assert_operator body.index("## New"), :<, body.index("## Also improved")
  end

  test "body has no Also improved section without changes, and no New section without features" do
    assert_not_includes period.body, "Also improved"
    shiplog_entries(:dark_mode_feature).update_columns(released_on: Date.new(2026, 9, 9))
    change("Only change", Date.new(2026, 10, 3))

    assert_not_includes period.body, "## New"
    assert_includes period.body, "## Also improved"
  end

  test "body links are absolute when canonical_url is set" do
    Shiplog.config.canonical_url = "https://example.com"

    assert_includes period.body, "[Dark mode](https://example.com/changelog/dark-mode)"
  end

  test "an entry without a slug is listed without a link" do
    change("No slug", Date.new(2026, 10, 3)).update_columns(slug: nil)

    assert_includes period.body, "- No slug: It works better."
    assert_not_includes period.body, "[No slug]"
  end

  test "skipped_change_titles includes changes the AI judged not customer-facing, not an admin's discards" do
    change("AI discarded", Date.new(2026, 10, 3), status: "discarded", discard_reason: Shiplog::Rewriter::NOT_CUSTOMER_FACING)
    change("Admin discarded", Date.new(2026, 10, 3), status: "discarded", discard_reason: "Not interesting")
    change("AI discarded in September", Date.new(2026, 9, 3), status: "discarded", discard_reason: Shiplog::Rewriter::NOT_CUSTOMER_FACING)

    assert_equal [ "AI discarded" ], period.skipped_change_titles
  end

  test "skipped_change_titles includes merged pull requests of the month with no entry" do
    Shiplog.config.repositories = [ "Trackberry/trackberry" ]
    Shiplog::PullRequest.create!(repository: shiplog_repositories(:app), node_id: "PR_loose", number: 200, title: "Loose fix", state: "merged",
      merged_at: Time.zone.local(2026, 10, 12, 10), author_login: "edouard")

    assert_equal [ "Loose fix" ], period.skipped_change_titles
  end

  test "skipped_change_titles leaves out pull requests linked to a public issue tree" do
    Shiplog.config.repositories = [ "Trackberry/trackberry" ]

    titles = period.skipped_change_titles

    assert_not_includes titles, "Add dark theme" # closes the dark mode feature
    assert_not_includes titles, "Validate CSV headers" # closes a child of the public bulk upload
  end

  test "skipped_change_titles leaves out pull requests with excluded labels, bot authors and roadmap-only repositories" do
    Shiplog.config.repositories = [ "Trackberry/trackberry", { name: "Trackberry/trackberry-ios", changelog: false } ]
    app = shiplog_repositories(:app)
    ios = shiplog_repositories(:ios)
    merged = lambda do |repository, number, title, **attributes|
      Shiplog::PullRequest.create!(repository:, node_id: "PR_skip_#{number}", number:, title:, state: "merged",
        merged_at: Time.zone.local(2026, 10, 12, 10), author_login: "edouard", **attributes)
    end
    merged.(app, 101, "Internal cleanup", labels: [ "internal" ])
    merged.(app, 102, "Bot bump", author_login: "dependabot[bot]")
    merged.(ios, 103, "iOS only")
    merged.(app, 104, "Real fix")
    merged.(app, 105, "Last month", merged_at: Time.zone.local(2026, 9, 12))

    titles = period.skipped_change_titles

    assert_includes titles, "Real fix"
    [ "Internal cleanup", "Bot bump", "iOS only", "Last month" ].each { |title| assert_not_includes titles, title }
  end

  test "skipped_change_titles leaves out pull requests that have an entry" do
    Shiplog.config.repositories = [ "Trackberry/trackberry" ]
    pull_request = Shiplog::PullRequest.create!(repository: shiplog_repositories(:app), node_id: "PR_with_entry", number: 201,
      title: "Has an entry", state: "merged", merged_at: Time.zone.local(2026, 10, 12, 10), author_login: "edouard")
    assert_includes period.skipped_change_titles, "Has an entry"
    Shiplog::Entry.create!(kind: "change", subject: pull_request, title: "Validated")

    assert_not_includes period.skipped_change_titles, "Has an entry"
  end

  test "content_digest changes when an entry of the month is updated or a new one approved, not for other months" do
    digest = period.content_digest
    assert_equal digest, period.content_digest

    shiplog_entries(:dark_mode_feature).update!(title: "Dark mode, finally")
    updated = period.content_digest
    assert_not_equal digest, updated

    added = change("Another one", Date.new(2026, 10, 12))
    approved = period.content_digest
    assert_not_equal updated, approved

    change("Other month", Date.new(2026, 9, 12))
    change("Draft in October", Date.new(2026, 10, 12), status: "draft")
    assert_equal approved, period.content_digest

    added.update!(body: "New text.")
    assert_not_equal approved, period.content_digest
  end

  test "a period has no GitHub url" do
    assert_nil period.url
  end

  test "PublicLinks uses an empty mount path for an engine mounted at the root" do
    assert_equal "", Shiplog::PublicLinks.mount_path
    assert_equal "/changelog", Shiplog::PublicLinks.changelog_url
    assert_equal "/changelog/dark-mode", Shiplog::PublicLinks.entry_url(shiplog_entries(:dark_mode_feature))
  end

  test "PublicLinks.entry_url respects canonical_url and is nil without a slug" do
    Shiplog.config.canonical_url = "https://example.com"
    entry = shiplog_entries(:dark_mode_feature)

    assert_equal "https://example.com/changelog/dark-mode", Shiplog::PublicLinks.entry_url(entry)
    assert_equal "https://example.com/changelog", Shiplog::PublicLinks.changelog_url
    entry.slug = nil
    assert_nil Shiplog::PublicLinks.entry_url(entry)
  end
end
