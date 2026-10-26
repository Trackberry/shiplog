require "test_helper"

class Shiplog::RoadmapsControllerTest < ActionDispatch::IntegrationTest
  test "renders three columns with translated headings" do
    get "/roadmap"
    assert_response :ok
    assert_select "section.shiplog-column[aria-labelledby]", 3
    assert_select "h2.shiplog-column__title", text: "In progress"
    assert_select "h2.shiplog-column__title", text: "Coming soon"
    assert_select "h2.shiplog-column__title", text: "Later"
  end

  test "shows approved entry titles and bodies" do
    get "/roadmap"
    assert_select "li.shiplog-card .shiplog-card__title", text: "Upload many shipments at once"
    assert_select "li.shiplog-card .shiplog-card__title", text: "Later thing"
    assert_includes response.body, "Soon you will be able to import a spreadsheet."
  end

  test "never leaks drafts or GitHub details" do
    get "/roadmap"
    assert_not_includes response.body, "Soon thing"
    assert_not_includes response.body, "Draft text."
    assert_not_includes response.body, "Bulk upload"
    assert_not_includes response.body, "github.com"
    assert_not_includes response.body, "#1"
  end

  test "empty columns say there is nothing yet" do
    Shiplog::Entry.roadmap.update_all(status: "draft")
    get "/roadmap"
    assert_select "p.shiplog-column__empty", text: "Nothing here yet", count: 3
    assert_select ".shiplog-column__count", text: "0", count: 3
  end

  test "escapes HTML in bodies" do
    shiplog_entries(:later_item_roadmap).update!(body: "<script>alert(1)</script>\n\nSecond paragraph")
    get "/roadmap"
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_select ".shiplog-card__body p", minimum: 2
  end

  test "uses the default stylesheet layout" do
    get "/roadmap"
    assert_select "link[rel=stylesheet][href=?]", "/shiplog/assets/#{Shiplog::VERSION}/shiplog.css", count: 1
    assert_select "main .shiplog-page.shiplog-page--roadmap"
  end

  test "the stylesheet link is emitted by the page, inside the body" do
    get "/roadmap"
    assert_select "head link[rel=stylesheet]", 0
    assert_select "body link[rel=stylesheet][href*='shiplog.css']", 1
  end

  test "the stylesheet link is also emitted inside a host layout" do
    Shiplog.config.public_layout = "custom"
    get "/roadmap"
    assert_select "link[rel=stylesheet][href*='shiplog.css']", 1
  end

  test "stylesheet false leaves out the bundled stylesheet" do
    Shiplog.config.stylesheet = false
    get "/roadmap"
    assert_select "link[rel=stylesheet]", 0
    assert_select ".shiplog-page"
  end

  test "page header has a title and a lede" do
    get "/roadmap"
    assert_select "header.shiplog-page__header h1.shiplog-page__title", text: "Roadmap"
    assert_select "header.shiplog-page__header p.shiplog-page__lede", text: /working on/
  end

  test "column headers show a count and a description" do
    get "/roadmap"
    assert_select "section.shiplog-column--in-progress header.shiplog-column__header" do
      assert_select ".shiplog-column__title", text: "In progress"
      assert_select ".shiplog-column__count", text: "1"
      assert_select ".shiplog-column__description", text: "What we're building now"
    end
    assert_select "section.shiplog-column--coming-soon .shiplog-column__description", text: "Planned next"
    assert_select "section.shiplog-column--later .shiplog-column__description", text: "On our radar"
  end

  test "columns are sections labelled by their title and hold ordered cards" do
    get "/roadmap"
    assert_select "section.shiplog-column[aria-labelledby=shiplog-column-later] h2#shiplog-column-later"
    assert_select "section.shiplog-column--later ol.shiplog-cards li.shiplog-card", 1
  end

  test "configured classes are added next to the BEM classes" do
    Shiplog.config.classes = { columns: "grid gap-6 md:grid-cols-3", card: "rounded-lg border", page_title: "text-3xl" }
    get "/roadmap"
    assert_select "div.shiplog-columns.grid.gap-6.md\\:grid-cols-3"
    assert_select "li.shiplog-card.rounded-lg.border"
    assert_select "h1.shiplog-page__title.text-3xl"
  end

  test "respects the configured public layout" do
    Shiplog.config.public_layout = "custom"
    get "/roadmap"
    assert_select "#host-layout-marker"
    assert_select "section.shiplog-column", 3
  end

  test "responds with conditional GET caching" do
    get "/roadmap"
    etag = response.headers["ETag"]
    assert etag.present?
    get "/roadmap", headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "ETag changes after approving an entry" do
    get "/roadmap"
    etag = response.headers["ETag"]
    shiplog_entries(:soon_item_roadmap).approve!(by: "ed@example.com")
    get "/roadmap", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes after pinning an issue to another column" do
    get "/roadmap"
    etag = response.headers["ETag"]
    shiplog_issues(:later_item).update_columns(pinned_column: "in_progress")
    get "/roadmap", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes when config.classes changes" do
    get "/roadmap"
    etag = response.headers["ETag"]
    Shiplog.config.classes = { card: "rounded" }
    get "/roadmap"
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes when config.stylesheet changes" do
    get "/roadmap"
    etag = response.headers["ETag"]
    Shiplog.config.stylesheet = false
    get "/roadmap"
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes with the gem version" do
    get "/roadmap"
    etag = response.headers["ETag"]
    original = Shiplog::VERSION
    begin
      silence_warnings { Shiplog.const_set(:VERSION, "9.9.9") }
      get "/roadmap"
      assert_not_equal etag, response.headers["ETag"]
    ensure
      silence_warnings { Shiplog.const_set(:VERSION, original) }
    end
  end

  test "ETag differs per locale" do
    get "/roadmap"
    english = response.headers["ETag"]
    with_extra_locale(:fr) { get "/roadmap" }
    assert_not_equal english, response.headers["ETag"]
  end

  test "each column carries a status marker for its modifier" do
    get "/roadmap"
    %w[in-progress coming-soon later].each do |column|
      assert_select "section.shiplog-column--#{column} h2.shiplog-column__title span.shiplog-column__marker.shiplog-column__marker--#{column}[aria-hidden=true]", 1
    end
    assert_select "h2.shiplog-column__title", text: "In progress"
  end

  test "a card shows the label of its repository" do
    Shiplog.config.repository_labels = { "Trackberry/trackberry" => "Web app" }
    get "/roadmap"
    assert_select "li.shiplog-card .shiplog-card__meta .shiplog-card__tag", text: "Web app", minimum: 1
  end

  test "repository labels may be callables evaluated in the view, and match case-insensitively" do
    Shiplog.config.repository_labels = { "trackberry/TRACKBERRY" => -> { t("shiplog.roadmap.title") + "!" } }
    get "/roadmap"
    assert_select ".shiplog-card__tag", text: "Roadmap!", minimum: 1
  end

  test "a card without a label or parts has no meta at all" do
    get "/roadmap"
    assert_select ".shiplog-card__meta", 0
    assert_select ".shiplog-card__tag", 0
  end

  test "a card says how many parts it includes only above one sub-issue" do
    parent = shiplog_issues(:bulk_upload)
    get "/roadmap"
    assert_select ".shiplog-card__meta", 0, "one sub-issue is not worth mentioning"

    add_child(parent, number: 90)
    get "/roadmap"
    assert_select "li.shiplog-card", text: /Upload many shipments/ do
      assert_select ".shiplog-card__meta", text: /Includes 2 parts/
      assert_select ".shiplog-card__tag", 0
    end
  end

  test "Recently shipped lists the last approved feature and change entries, newest first" do
    shipped = [ [ "Oldest", "2026-08-30", "change" ], [ "Middle", "2026-09-15", "feature" ], [ "Newest", "2026-10-20", "change" ] ].map do |title, date, kind|
      approved_entry(title:, released_on: date, kind:)
    end
    get "/roadmap"

    assert_select "section.shiplog-shipped[aria-labelledby=shiplog-recently-shipped]" do
      assert_select "h2.shiplog-shipped__title#shiplog-recently-shipped", text: "Recently shipped"
      assert_select "ul.shiplog-shipped__list li.shiplog-shipped__item", 4 # the three above and the Dark mode fixture
      titles = css_select("li.shiplog-shipped__item a.shiplog-shipped__link").map(&:text)
      assert_equal [ "Newest", "Dark mode", "Middle", "Oldest" ], titles
      assert_select "a.shiplog-shipped__link[href=?]", "/changelog#shiplog-month-2026-10", text: "Newest"
      assert_select "a.shiplog-shipped__link[href=?]", "/changelog#shiplog-month-2026-08", text: "Oldest"
      assert_select "time.shiplog-shipped__date[datetime=?]", "2026-10-20"
      assert_select "a.shiplog-shipped__link--all[href=?]", "/changelog", text: "See the full changelog"
    end
    assert_equal 3, shipped.size
  end

  test "Recently shipped shows only the configured count, ignoring drafts and roadmap entries" do
    Shiplog.config.roadmap_shipped_count = 1
    approved_entry(title: "Newest", released_on: "2026-10-20", kind: "feature")
    approved_entry(title: "Draft", released_on: "2026-10-25", kind: "feature", status: "draft")
    get "/roadmap"

    assert_select "li.shiplog-shipped__item", 1
    assert_select ".shiplog-shipped__link", text: "Newest"
    assert_select ".shiplog-shipped__link", text: "Draft", count: 0
    assert_select ".shiplog-shipped__link", text: "Upload many shipments at once", count: 0
  end

  test "Recently shipped is hidden when the count is zero" do
    Shiplog.config.roadmap_shipped_count = 0
    get "/roadmap"
    assert_select "section.shiplog-shipped", 0
  end

  test "Recently shipped is hidden when nothing has shipped" do
    Shiplog::Entry.where(kind: %w[feature change]).delete_all
    get "/roadmap"
    assert_select "section.shiplog-shipped", 0
    assert_not_includes response.body, "See the full changelog"
  end

  test "the footnote and the suggest link render only when configured" do
    get "/roadmap"
    assert_select ".shiplog-footnote", 0
    assert_select ".shiplog-footnote__link", 0

    Shiplog.config.feedback_path = "/feedback/new"
    get "/roadmap"
    assert_select "p.shiplog-footnote a.shiplog-footnote__link[href=?]", "/feedback/new", text: "Suggest a feature"

    Shiplog.config.feedback_path = -> { main_app.about_path }
    get "/roadmap"
    assert_select "a.shiplog-footnote__link[href=?]", "/about"
  end

  test "the footnote text comes from I18n and shows without a feedback path" do
    I18n.backend.store_translations(:en, shiplog: { roadmap: { footnote: "Plans change." } })
    get "/roadmap"
    assert_select "p.shiplog-footnote", text: "Plans change."
    assert_select "a.shiplog-footnote__link", 0
  ensure
    I18n.backend.reload!
  end

  test "the new class keys apply" do
    Shiplog.config.repository_labels = { "Trackberry/trackberry" => "Web" }
    Shiplog.config.feedback_path = "/feedback"
    Shiplog.config.classes = { column_marker: "m-x", card_meta: "meta-x", card_tag: "tag-x", shipped: "shipped-x",
      shipped_title: "st-x", shipped_list: "sl-x", shipped_item: "si-x", shipped_link: "slink-x", shipped_date: "sd-x",
      footnote: "fn-x", footnote_link: "fnl-x" }
    get "/roadmap"

    %w[.shiplog-column__marker.m-x .shiplog-card__meta.meta-x .shiplog-card__tag.tag-x .shiplog-shipped.shipped-x
       .shiplog-shipped__title.st-x .shiplog-shipped__list.sl-x .shiplog-shipped__item.si-x .shiplog-shipped__link.slink-x
       .shiplog-shipped__date.sd-x .shiplog-footnote.fn-x .shiplog-footnote__link.fnl-x].each do |selector|
      assert_select selector, minimum: 1
    end
  end

  test "ETag changes after approving a changelog entry" do
    entry = shiplog_entries(:csv_change_draft)
    entry.update!(released_on: "2026-10-15")
    get "/roadmap"
    etag = response.headers["ETag"]

    travel 1.minute do
      entry.approve!(by: "ed@example.com")
    end
    get "/roadmap", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_not_equal etag, response.headers["ETag"]
  end

  test "ETag changes with the roadmap options" do
    get "/roadmap"
    etag = response.headers["ETag"]
    Shiplog.config.roadmap_shipped_count = 1
    get "/roadmap"
    assert_not_equal etag, response.headers["ETag"]
  end

  test "the query count does not grow with the number of roadmap items" do
    get "/roadmap" # warm up caches and schema loading
    seed = ->(count) do
      count.times do |index|
        parent = add_issue(shiplog_repositories(index.even? ? :app : :ios), number: 200 + index)
        2.times { |child| add_child(parent, number: 300 + index * 10 + child) }
        Shiplog::Entry.create!(kind: "roadmap", status: "approved", subject: parent, title: "Item #{index}", body: "Body")
      end
    end
    Shiplog.config.repository_labels = { "Trackberry/trackberry-ios" => "iPhone" }

    seed.call(2)
    few = count_queries { get "/roadmap" }
    Shiplog::Issue.where("number >= 200").destroy_all
    seed.call(8)
    many = count_queries { get "/roadmap" }

    assert_response :ok
    assert_select "li.shiplog-card", minimum: 8
    assert_equal few, many
  end

  private

  def add_issue(repository, number:, parent: nil)
    Shiplog::Issue.create!(repository:, node_id: "I_test_#{number}", number:, title: "Issue #{number}", body: "Body", state: "open",
      labels: [ "public" ], assignees_count: 0, parent_node_id: parent&.node_id, url: "https://github.com/x/y/issues/#{number}",
      github_created_at: Time.current, github_updated_at: Time.current)
  end

  def add_child(parent, number:) = add_issue(parent.repository, number:, parent:)

  def approved_entry(title:, released_on:, kind:, status: "approved")
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: title,
      committed_at: Time.current, url: "https://github.com/x/y/commit/1")
    Shiplog::Entry.create!(kind:, status:, subject: commit, title:, body: "Body", released_on:, approved_at: Time.current)
  end
end
