require "test_helper"

class Shiplog::Admin::AnnouncementsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  ADMIN = "/admin/shiplog".freeze

  setup do
    travel_to Time.zone.local(2026, 10, 27, 10)
    # October has the fixture's Dark mode; September gets an approved change of its own.
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: "m",
      committed_at: Time.current, url: "https://example.com/commit/1")
    Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title: "Sturdier imports", body: "Imports are sturdier.",
      released_on: Date.new(2026, 9, 14), approved_at: Time.current, slug: "sturdier-imports")
  end

  def draft!(month = Date.new(2026, 10, 1)) = Shiplog::Announcements.draft(month:)

  def edit_path(entry) = "#{ADMIN}/entries/#{entry.id}/edit"

  def export_path(entry, **query) = "#{ADMIN}/entries/#{entry.id}/export#{"?#{query.to_query}" if query.any?}"

  test "the inbox offers to draft the current and the previous month" do
    get "#{ADMIN}/"

    assert_response :ok
    assert_select "form[action=?][method=post]", "#{ADMIN}/announcements?month=2026-10" do
      assert_select "button", text: "Draft announcement for October 2026"
    end
    assert_select "form[action=?] button", "#{ADMIN}/announcements?month=2026-09", text: "Draft announcement for September 2026"
    assert_select "button", text: /Draft announcement for/, count: 2
  end

  test "the buttons are also offered when announcements are published externally" do
    Shiplog.config.announcements = :external

    get "#{ADMIN}/"

    assert_select "button", text: /Draft announcement for/, count: 2
  end

  test "the inbox offers the Announcement kind filter only when announcements are on" do
    get "#{ADMIN}/"
    assert_select "a.shiplog-admin-filters__link", text: "Announcement"

    Shiplog.config.announcements = false
    get "#{ADMIN}/"
    assert_select "a.shiplog-admin-filters__link", text: "Announcement", count: 0
  end

  test "the inbox has no draft buttons when announcements are off" do
    Shiplog.config.announcements = false

    get "#{ADMIN}/"

    assert_response :ok
    assert_select "button", text: /Draft announcement for/, count: 0
  end

  test "drafting the previous month creates the draft and opens it" do
    assert_difference -> { Shiplog::Entry.where(kind: "announcement").count }, 1 do
      post "#{ADMIN}/announcements", params: { month: "2026-09" }
    end

    entry = Shiplog::Entry.find_by!(kind: "announcement")
    assert_redirected_to edit_path(entry)
    assert_equal "2026-09", entry.slug
    assert_equal "September 2026", entry.title
    follow_redirect!
    assert_select ".shiplog-admin__flash", text: /Announcement draft ready/
  end

  test "drafting a month again opens the same announcement" do
    post "#{ADMIN}/announcements", params: { month: "2026-09" }
    first = Shiplog::Entry.find_by!(kind: "announcement")

    assert_no_difference -> { Shiplog::Entry.count } do
      post "#{ADMIN}/announcements", params: { month: "2026-09" }
    end

    assert_redirected_to edit_path(first)
  end

  test "drafting keeps the inbox filters" do
    post "#{ADMIN}/announcements", params: { month: "2026-09", status: "draft", kind: "announcement" }

    entry = Shiplog::Entry.find_by!(kind: "announcement")
    assert_redirected_to "#{edit_path(entry)}?kind=announcement&status=draft"
  end

  test "a month with nothing to announce goes back to the inbox with the alert" do
    shiplog_entries(:dark_mode_feature).update_columns(released_on: Date.new(2026, 9, 9))
    Shiplog::Entry.find_by!(slug: "sturdier-imports").update_columns(status: "draft")

    assert_no_difference -> { Shiplog::Entry.count } do
      post "#{ADMIN}/announcements", params: { month: "2026-10" }
    end

    assert_redirected_to "#{ADMIN}/"
    follow_redirect!
    assert_select ".shiplog-admin__flash", text: /no approved feature or change to announce/
  end

  test "a month that is not draftable is not found" do
    [ "2026-08", "2026-11", "garbage", "", "2026-10-01" ].each do |month|
      post "#{ADMIN}/announcements", params: { month: }
      assert_response :not_found, month.inspect
    end
    assert_equal 0, Shiplog::Entry.where(kind: "announcement").count
  end

  test "drafting is not possible when announcements are off" do
    Shiplog.config.announcements = false

    post "#{ADMIN}/announcements", params: { month: "2026-10" }

    assert_response :not_found
    assert_equal 0, Shiplog::Entry.where(kind: "announcement").count
  end

  test "drafting requires an authorised admin" do
    Shiplog.config.authorize_admin = ->(_controller) { false }

    post "#{ADMIN}/announcements", params: { month: "2026-10" }

    assert_not_equal 302, response.status
    assert_equal 0, Shiplog::Entry.where(kind: "announcement").count
  end

  test "the inbox lists announcement rows, whose Period subject has no repository" do
    entry = draft!

    get "#{ADMIN}/", params: { kind: "announcement" }

    assert_response :ok
    assert_select "#shiplog-entry-#{entry.id}", text: /October 2026/
    get "#{ADMIN}/"
    assert_response :ok
    assert_select "#shiplog-entry-#{entry.id}"
  end

  test "the inbox lists approved announcements too" do
    entry = draft!
    entry.approve!(by: "ed@example.com")

    get "#{ADMIN}/", params: { status: "approved", kind: "announcement" }

    assert_response :ok
    assert_select "#shiplog-entry-#{entry.id}"
  end

  test "the edit page shows the preview and the export links, without an area or a release date" do
    entry = draft!
    entry.update!(title: "October recap", body: "Intro.\n\n## Highlights\n\n- [Dark mode](/changelog/dark-mode)")

    get edit_path(entry)

    assert_response :ok
    assert_select "input[name='entry[title]'][value=?]", "October recap"
    assert_select "textarea[name='entry[body]']"
    assert_select "select[name='entry[area_id]']", count: 0
    assert_select "input[name='entry[released_on]']", count: 0
    assert_select "select[name='entry[changelog_kind]']", count: 0
    assert_select ".shiplog-admin-preview" do
      assert_select "h2", text: "October recap"
      assert_select "h3", text: "Highlights"
      assert_select "a[href=?]", "/changelog/dark-mode"
    end
    assert_select "a[href=?]", export_path(entry, as: "markdown"), text: "Markdown"
    assert_select "a[href=?]", export_path(entry, as: "html"), text: "HTML"
    assert_select "a[href=?]", export_path(entry, as: "text"), text: "Plain text"
    assert_select "p", text: /Approve it to publish it/
  end

  test "the edit page of an approved announcement links the public page and says the app is being told" do
    entry = draft!
    entry.approve!(by: "ed@example.com")

    get edit_path(entry)

    assert_select "a[href=?]", "/changelog/2026-10", text: "View the public page"
    assert_select "p", text: /Notifying your app/
  end

  test "the edit page says when the app was notified, and when it waits for translations" do
    entry = draft!
    entry.approve!(by: "ed@example.com")
    entry.update_columns(announced_at: Time.current)

    get edit_path(entry)
    assert_select "p", text: /Your app was notified/

    entry.update_columns(announced_at: nil)
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = ->(_prompt) { "{}" }
    get edit_path(entry)
    assert_select "p", text: /once every translation is current/
  end

  test "the edit page offers an export per configured locale" do
    Shiplog.config.locales = [ :es ]
    entry = draft!

    get edit_path(entry)

    assert_select "a[href=?]", export_path(entry, as: "markdown")
    assert_select "a[href=?]", export_path(entry, as: "markdown", export_locale: "es")
  end

  test "the edit page of a feature keeps its area and release date fields" do
    get edit_path(shiplog_entries(:dark_mode_feature))

    assert_select "select[name='entry[area_id]']"
    assert_select "input[name='entry[released_on]']"
    assert_select ".shiplog-admin-preview", count: 0
  end

  test "saving an announcement stores the title and the body and ignores the release date and the area" do
    entry = draft!
    area = Shiplog::Area.create!(name: "Billing")

    patch "#{ADMIN}/entries/#{entry.id}", params: { entry: { title: "New title", body: "New **body**", released_on: "2026-01-01", area_id: area.id } }

    assert_redirected_to "#{ADMIN}/"
    entry.reload
    assert_equal "New title", entry.title
    assert_equal "New **body**", entry.body
    assert_equal Date.new(2026, 10, 31), entry.released_on
    assert_nil entry.area_id
    assert_not entry.area_set_by_admin
  end

  test "saving an announcement cannot change its kind" do
    entry = draft!

    patch "#{ADMIN}/entries/#{entry.id}", params: { entry: { title: "T", body: "B", changelog_kind: "feature" } }

    assert entry.reload.announcement?
  end

  test "approving an announcement from the admin enqueues its announcement" do
    entry = draft!

    assert_enqueued_with(job: Shiplog::AnnounceJob, args: [ entry ]) do
      post "#{ADMIN}/entries/#{entry.id}/approval"
    end
    assert entry.reload.approved?
    assert_equal "2026-10", entry.slug
  end

  test "Notify now enqueues a forced announcement and opens the edit page" do
    entry = draft!
    entry.approve!(by: "ed@example.com")
    clear_enqueued_jobs

    assert_enqueued_with(job: Shiplog::AnnounceJob, args: [ entry, { force: true } ]) do
      post "#{ADMIN}/entries/#{entry.id}/announcement_notification"
    end

    assert_redirected_to edit_path(entry)
    follow_redirect!
    assert_select ".shiplog-admin__flash", text: /will be notified/
  end

  test "Notify now is not found for a feature" do
    assert_no_enqueued_jobs only: Shiplog::AnnounceJob do
      post "#{ADMIN}/entries/#{shiplog_entries(:dark_mode_feature).id}/announcement_notification"
    end
    assert_response :not_found
  end

  test "the edit page shows Notify now for an approved announcement not announced yet only" do
    entry = draft!
    get edit_path(entry)
    assert_select "button", text: "Notify now", count: 0

    entry.approve!(by: "ed@example.com")
    get edit_path(entry)
    assert_select "form[action=?] button", "#{ADMIN}/entries/#{entry.id}/announcement_notification", text: "Notify now"

    entry.update_columns(announced_at: Time.current)
    get edit_path(entry)
    assert_select "button", text: "Notify now", count: 0
  end

  test "with no rewriter and locales, the edit page does not say it waits for translations" do
    Shiplog.config.locales = [ :es ]
    entry = draft!
    entry.approve!(by: "ed@example.com")

    get edit_path(entry)

    assert_select "p", text: /once every translation is current/, count: 0
  end

  test "exports the Markdown by default, as an attachment" do
    entry = draft!
    entry.update!(title: "October recap", body: "Intro.\n\n## Highlights")

    get export_path(entry)

    assert_response :ok
    assert_equal "text/markdown; charset=utf-8", response.headers["Content-Type"]
    assert_match(/\Aattachment; filename="2026-10\.md"/, response.headers["Content-Disposition"])
    assert_equal "# October recap\n\nIntro.\n\n## Highlights\n", response.body
  end

  test "exports HTML and plain text" do
    entry = draft!
    entry.update!(title: "October recap", body: "Intro with [a link](https://example.com).\n\n## Highlights")

    get export_path(entry, as: "html")

    assert_response :ok
    assert_equal "text/html; charset=utf-8", response.headers["Content-Type"]
    assert_match(/\Aattachment; filename="2026-10\.html"/, response.headers["Content-Disposition"])
    assert_includes response.body, "<h1>October recap</h1>"
    assert_includes response.body, %(<a href="https://example.com">a link</a>)
    assert_includes response.body, "<h2>Highlights</h2>"

    get export_path(entry, as: "text")

    assert_response :ok
    assert_equal "text/plain; charset=utf-8", response.headers["Content-Type"]
    assert_match(/\Aattachment; filename="2026-10\.txt"/, response.headers["Content-Disposition"])
    assert_equal "October recap\n\nIntro with a link (https://example.com).\n\nHighlights\n", response.body
  end

  test "the HTML export escapes a script in the title and the body" do
    entry = draft!
    entry.update!(title: "<script>alert(1)</script>", body: "<script>alert(2)</script>")

    get export_path(entry, as: "html")

    assert_not_includes response.body, "<script>"
    assert_includes response.body, "<h1>&lt;script&gt;alert(1)&lt;/script&gt;</h1>"
    assert_includes response.body, "&lt;script&gt;alert(2)&lt;/script&gt;"
  end

  test "?locale returns the translation of a configured locale" do
    Shiplog.config.locales = [ :es ]
    entry = draft!
    entry.translations.create!(locale: "es", title: "Resumen de octubre", body: "## Destacados\n\nTexto",
      source_digest: entry.translation_source_digest)

    get export_path(entry, export_locale: "es")

    assert_response :ok
    assert_match(/filename="2026-10-es\.md"/, response.headers["Content-Disposition"])
    assert_equal "# Resumen de octubre\n\n## Destacados\n\nTexto\n", response.body

    get export_path(entry, as: "html", export_locale: "es")
    assert_includes response.body, "<h1>Resumen de octubre</h1>"
    assert_includes response.body, "<h2>Destacados</h2>"

    get export_path(entry, as: "text", export_locale: "es")
    assert_equal "Resumen de octubre\n\nDestacados\n\nTexto\n", response.body
  end

  test "a configured locale without a translation exports the English text" do
    Shiplog.config.locales = [ :es ]
    entry = draft!

    get export_path(entry, export_locale: "es")

    assert_response :ok
    assert_includes response.body, "# October 2026"
  end

  test "the default locale can be named explicitly" do
    entry = draft!

    get export_path(entry, export_locale: "en")

    assert_response :ok
    assert_match(/filename="2026-10\.md"/, response.headers["Content-Disposition"])
  end

  test "an unconfigured locale is not found" do
    entry = draft!

    get export_path(entry, export_locale: "es") # available to I18n, but not in config.locales
    assert_response :not_found

    with_extra_locale(:fr) do
      Shiplog.config.locales = [ :es ]
      get export_path(entry, export_locale: "fr")
      assert_response :not_found
    end
  end

  test "a configured locale the host's I18n does not know can still be exported" do
    Shiplog.config.locales = [ :xx ]
    entry = draft!

    get export_path(entry, export_locale: "xx")

    assert_response :ok
  end

  test "an unknown format is not found" do
    get export_path(draft!, as: "pdf")

    assert_response :not_found
  end

  test "only announcements can be exported" do
    get export_path(shiplog_entries(:dark_mode_feature))

    assert_response :not_found
  end

  test "an unknown entry is not found" do
    get "#{ADMIN}/entries/0/export"

    assert_response :not_found
  end

  test "exports need an authorised admin" do
    entry = draft!
    Shiplog.config.authorize_admin = ->(_controller) { false }

    get export_path(entry)

    assert_not_equal 200, response.status
    assert_not_includes response.body, "October 2026"
  end

  test "saving a translation of an approved announcement enqueues the announcement job" do
    Shiplog.config.locales = [ :es ]
    entry = draft!
    entry.approve!(by: "ed@example.com")
    clear_enqueued_jobs

    assert_enqueued_with(job: Shiplog::AnnounceJob, args: [ entry ]) do
      patch "#{ADMIN}/entries/#{entry.id}/translations/es", params: { translation: { title: "Resumen", body: "Texto" } }
    end

    assert_redirected_to edit_path(entry)
  end

  test "saving a translation of a feature enqueues no announcement job" do
    Shiplog.config.locales = [ :es ]
    feature = shiplog_entries(:dark_mode_feature)

    assert_no_enqueued_jobs only: Shiplog::AnnounceJob do
      patch "#{ADMIN}/entries/#{feature.id}/translations/es", params: { translation: { title: "Modo oscuro", body: "Texto" } }
    end
  end

  test "the admin's translation completes the announcement: the hook is called once it is saved" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = ->(_prompt) { "{}" }
    calls = []
    Shiplog.config.on_announcement_approved = ->(announcement) { calls << announcement }
    entry = draft!
    entry.approve!(by: "ed@example.com")

    perform_enqueued_jobs(only: Shiplog::AnnounceJob)
    assert_empty calls

    patch "#{ADMIN}/entries/#{entry.id}/translations/es", params: { translation: { title: "Resumen", body: "Texto" } }
    perform_enqueued_jobs(only: Shiplog::AnnounceJob)

    assert_equal [ entry ], calls
  end
end
