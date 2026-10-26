require "test_helper"

# A host whose locale has no Shiplog translations (e.g. fr) gets English, not translation-missing spans.
class Shiplog::LocaleFallbackTest < ActionDispatch::IntegrationTest
  NEW_KEYS = /shiplog\.(switcher\.|roadmap\.(parts|shipped_heading|shipped_date_format|full_changelog|suggest))/

  setup do
    I18n.backend.eager_load! # translations stored before the files load would be overwritten by them
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: "Shipped thing",
      committed_at: Time.current, url: "https://github.com/x/y/commit/1")
    Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title: "Shipped thing", body: "Body",
      released_on: Date.new(2026, 10, 1), approved_at: Time.current)
    parent = shiplog_issues(:bulk_upload)
    2.times { |i| Shiplog::Issue.create!(repository: parent.repository, parent:, node_id: "I_fr#{i}", number: 900 + i, title: "Part #{i}", state: "open") }
    Shiplog.config.feedback_path = "/feedback"
  end

  # French with Rails' month names only: a host locale that has no Shiplog translations.
  def in_french
    with_extra_locale(:fr) do
      I18n.backend.store_translations(:fr, date: { month_names: [ nil ] + %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre] })
      yield
    end
  end

  def missing_new_keys(body) = body.scan(/translation missing: ([^"']+)/i).flatten.grep(NEW_KEYS)

  test "the roadmap falls back to English defaults for the new keys" do
    in_french do
      get "/roadmap"

      assert_response :ok
      assert_empty missing_new_keys(response.body)
      assert_select "nav.shiplog-switcher[aria-label=?]", "Product updates"
      assert_select "nav.shiplog-switcher a", text: "Changelog"
      assert_select ".shiplog-card__meta", text: /Includes 3 parts/
      assert_select "h2", text: "Recently shipped"
      assert_select "a", text: "See the full changelog"
      assert_select "time.shiplog-shipped__date", text: "1 octobre"
      assert_select "a", text: "Suggest a feature"
    end
  end

  test "the changelog falls back to English defaults for the switcher" do
    in_french do
      get "/changelog"

      assert_empty missing_new_keys(response.body)
      assert_select "nav.shiplog-switcher[aria-label=?]", "Product updates"
    end
  end

  test "the nav label is a plain attribute value even when the translation contains markup" do
    I18n.backend.store_translations(:en, shiplog: { switcher: { label: "<b>Updates</b>" } })
    get "/roadmap"
    assert_select "nav.shiplog-switcher[aria-label=?]", "<b>Updates</b>"
    assert_no_match(/aria-label="<b>/, response.body)
  ensure
    I18n.backend.reload!
  end

  test "the shipped date falls back to a literal format" do
    I18n.backend.store_translations(:en, shiplog: { roadmap: { shipped_date_format: nil } })
    get "/roadmap"

    assert_select "time.shiplog-shipped__date", text: "1 October"
  ensure
    I18n.backend.reload!
  end

  # Every public page, under a locale whose backend is empty (but for Rails' month names): no translation-missing
  # output anywhere, in the HTML or in the feed.
  test "no public page or the feed shows a missing translation" do
    now = Time.current
    Shiplog::Entry.insert_all!(Array.new(35) do |i|
      { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: 50_000 + i, title: "Bulk #{i}", body: "Body #{i}",
        slug: "bulk-#{i}", released_on: Date.new(2026, 9, 1) - i, approved_at: now, created_at: now, updated_at: now }
    end)
    first_area = Shiplog::Area.create!(name: "Billing", slug: "billing", position: 1)
    Shiplog::Area.create!(name: "Search", slug: "search", position: 2)
    Shiplog::Entry.where(slug: "bulk-1").update_all(area_id: first_area.id)
    Shiplog::Entry.where(slug: "bulk-2").update_all(area_id: Shiplog::Area.find_by!(slug: "search").id)
    Shiplog.config.product_name = "Acme"

    in_french do
      [ "/roadmap", "/changelog", "/changelog?page=2", "/changelog?q=bulk", "/changelog?area=billing", "/changelog?q=zzzz",
        "/changelog/dark-mode", "/changelog/bulk-10", "/changelog.atom" ].each do |path|
        get path
        assert_response :ok, path
        assert_no_match(/translation[_ ]missing/i, response.body, "#{path} shows a missing translation")
      end
    end
  end

  test "the roadmap's empty columns and the feed's default title fall back to English" do
    Shiplog::Entry.roadmap.delete_all
    in_french do
      get "/roadmap"
      assert_no_match(/translation[_ ]missing/i, response.body)
      assert_select ".shiplog-column__empty", text: "Nothing here yet", minimum: 1
      assert_select "h1", text: "Roadmap"

      get "/changelog.atom"
      assert_select "title", text: "Changelog"
    end
  end
end
