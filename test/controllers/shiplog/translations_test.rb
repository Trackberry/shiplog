require "test_helper"
require "rexml/document"

# The public pages under a translated locale: the translation when it exists and is current, English otherwise.
class Shiplog::TranslationsTest < ActionDispatch::IntegrationTest
  setup do
    Shiplog.config.locales = [ :es ]
    @dark = shiplog_entries(:dark_mode_feature)
    @roadmap = shiplog_entries(:bulk_upload_roadmap)
    @csv = shiplog_entries(:csv_change_draft)
    @csv.update_columns(status: "approved", released_on: Date.new(2026, 9, 15), slug: "better-csv-validation", approved_at: Time.current)
  end

  def translate!(entry, title, body, locale: "es", **attributes)
    entry.translations.create!(locale:, title:, body:, source_digest: entry.translation_source_digest, **attributes)
  end

  def in_spanish(&block) = I18n.with_locale(:es, &block)

  def titles = css_select(".shiplog-entry__title").map(&:text)

  test "the roadmap shows translated cards and the recently shipped titles" do
    translate!(@roadmap, "Sube muchos envíos a la vez", "Pronto podrás importar una hoja de cálculo.")
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")

    in_spanish { get "/roadmap" }

    assert_select ".shiplog-card__title", text: "Sube muchos envíos a la vez"
    assert_select ".shiplog-card__body", text: "Pronto podrás importar una hoja de cálculo."
    assert_select ".shiplog-card__title", text: "Upload many shipments at once", count: 0
    assert_select ".shiplog-shipped__link", text: "Modo oscuro"
    assert_select ".shiplog-card__title", text: "Later thing" # no translation: English
  end

  test "the roadmap stays English under the default locale" do
    translate!(@roadmap, "Sube muchos envíos a la vez", "Texto")

    get "/roadmap"

    assert_select ".shiplog-card__title", text: "Upload many shipments at once"
    assert_select ".shiplog-card__title", text: "Sube muchos envíos a la vez", count: 0
  end

  test "the changelog list shows translated titles and bodies" do
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")

    in_spanish { get "/changelog" }

    assert_includes titles, "Modo oscuro"
    assert_select ".shiplog-entry__title a[href=?]", "/changelog/dark-mode", text: "Modo oscuro"
    assert_select ".shiplog-entry__body", text: "Cambia a un tema oscuro."
    assert_includes titles, "Better CSV validation"
  end

  test "the permalink shows the translation in the page, the title, the description and the Open Graph tags" do
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")

    in_spanish { get "/changelog/dark-mode" }

    assert_select ".shiplog-entry__title", text: "Modo oscuro"
    assert_select ".shiplog-entry__body", text: "Cambia a un tema oscuro."
    assert_select "title", text: "Modo oscuro · Novedades"
    assert_select "meta[name=description][content=?]", "Cambia a un tema oscuro."
    assert_select "meta[property='og:title'][content=?]", "Modo oscuro"
    assert_select "meta[property='og:description'][content=?]", "Cambia a un tema oscuro."
    assert_select "html[lang=es]"
  end

  test "the permalink's newer and older links use translated titles" do
    translate!(@csv, "Mejor validación de CSV", "Texto")
    translate!(@dark, "Modo oscuro", "Texto")

    in_spanish { get "/changelog/better-csv-validation" }
    assert_select "a.shiplog-permalink__nav-link--newer", text: /Modo oscuro/

    in_spanish { get "/changelog/dark-mode" }
    assert_select "a.shiplog-permalink__nav-link--older", text: /Mejor validación de CSV/
  end

  test "the feed shows translated titles and content, declares the language and keeps the English ids" do
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")

    in_spanish { get "/changelog.atom" }

    doc = REXML::Document.new(response.body)
    assert_equal "es", doc.root.attributes["xml:lang"]
    ns = { "a" => "http://www.w3.org/2005/Atom" }
    entry = REXML::XPath.match(doc, "//a:entry", ns).find { |node| REXML::XPath.first(node, "a:id", ns).text.end_with?("/changelog/dark-mode") }
    assert_equal "Modo oscuro", REXML::XPath.first(entry, "a:title", ns).text
    assert_includes REXML::XPath.first(entry, "a:content", ns).text, "Cambia a un tema oscuro."
    assert_equal "http://www.example.com/changelog/dark-mode", REXML::XPath.first(entry, "a:link", ns).attributes["href"]
  end

  test "the feed declares the English language by default" do
    get "/changelog.atom"

    assert_equal "en", REXML::Document.new(response.body).root.attributes["xml:lang"]
  end

  test "English shows when the translation is missing, for another locale, or stale" do
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")
    stale = translate!(@csv, "Mejor validación de CSV", "Texto")
    stale.update_columns(source_digest: "an older English text")

    in_spanish do
      get "/changelog"
      assert_includes titles, "Modo oscuro"
      assert_includes titles, "Better CSV validation"
      assert_not_includes titles, "Mejor validación de CSV"

      get "/changelog/better-csv-validation"
      assert_select ".shiplog-entry__title", text: "Better CSV validation"
      assert_select "meta[property='og:title'][content=?]", "Better CSV validation"

      get "/roadmap"
      assert_select ".shiplog-card__title", text: "Upload many shipments at once"
    end
  end

  test "a translation stops showing as soon as the English text changes" do
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")
    @dark.update_columns(title: "Dark mode, everywhere", updated_at: 1.minute.from_now)

    in_spanish { get "/changelog" }

    assert_includes titles, "Dark mode, everywhere"
    assert_not_includes titles, "Modo oscuro"
  end

  test "translations of entries that are no longer approved are never shown" do
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")
    @dark.update_columns(status: "discarded")

    in_spanish do
      get "/changelog"
      assert_not_includes titles, "Modo oscuro"
      get "/changelog/dark-mode"
      assert_response :not_found
      get "/changelog.atom"
      assert_no_match(/Modo oscuro/, response.body)
    end
  end

  test "slugs stay English" do
    translate!(@dark, "Modo oscuro", "Texto")

    in_spanish { get "/changelog/modo-oscuro" }
    assert_response :not_found
    in_spanish { get "/changelog/dark-mode" }
    assert_response :ok
  end

  test "a locale that is not configured shows English even with a translation row" do
    translate!(@dark, "Modo oscuro", "Texto")
    Shiplog.config.locales = []

    in_spanish { get "/changelog" }

    assert_includes titles, "Dark mode"
  end

  test "an admin-edited translation shows like any other" do
    translate!(@dark, "Modo noche", "Texto", edited_by_admin: true)

    in_spanish { get "/changelog" }

    assert_includes titles, "Modo noche"
  end

  test "image alt texts default to the shown title" do
    translate!(@dark, "Modo oscuro", "Texto")

    in_spanish { assert_equal "Modo oscuro", @dark.reload.image_alt(Struct.new(:blob_id).new(1)) }
    assert_equal "Dark mode", @dark.image_alt(Struct.new(:blob_id).new(1))
  end

  # --- search ---

  test "under a translated locale, search matches the translated title or body, or the English text" do
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")

    in_spanish do
      get "/changelog", params: { q: "OSCURO" }
      assert_equal [ "Modo oscuro" ], titles
      get "/changelog", params: { q: "cambia tema" }
      assert_equal [ "Modo oscuro" ], titles
      get "/changelog", params: { q: "dark theme" }
      assert_equal [ "Modo oscuro" ], titles
      get "/changelog", params: { q: "csv" }
      assert_equal [ "Better CSV validation" ], titles
      get "/changelog", params: { q: "oscuro csv" }
      assert_empty titles
    end
  end

  test "the English locale does not search translations" do
    translate!(@dark, "Modo oscuro", "Texto")

    get "/changelog", params: { q: "oscuro" }

    assert_empty titles
  end

  test "search ignores translations of another locale and stale ones" do
    translate!(@dark, "Mode sombre", "Texte", locale: "fr")
    stale = translate!(@csv, "Validación antigua", "Texto")
    stale.update_columns(source_digest: "older")

    in_spanish do
      get "/changelog", params: { q: "sombre" }
      assert_empty titles
      get "/changelog", params: { q: "antigua" }
      assert_empty titles
    end
  end

  test "search under a translated locale still escapes LIKE wildcards" do
    translate!(@dark, "Modo oscuro", "Un 100% oscuro.")
    translate!(@csv, "Validación", "Sin comodines")

    in_spanish do
      get "/changelog", params: { q: "%" }
      assert_equal [ "Modo oscuro" ], titles
      get "/changelog", params: { q: "_" }
      assert_empty titles
    end
  end

  HOSTILE_TERMS = [ "a:b", "x:pattern", "x:locale", "x:pattern') OR 1=1 --", "'", "\\", "%", "_" ].freeze

  def probe!(term)
    @probes = @probes.to_i + 1
    commit = Shiplog::Commit.create!(repository: shiplog_repositories(:app), sha: SecureRandom.hex(20), message: "Probe", committed_at: Time.current,
      url: "https://github.com/x/y/commit/#{@probes}")
    entry = Shiplog::Entry.create!(kind: "change", status: "approved", subject: commit, title: "Probe #{term}", body: "Plain",
      released_on: Date.new(2026, 9, 1), approved_at: Time.current, slug: "probe-#{SecureRandom.hex(3)}")
    translate!(entry, "Sonda #{term}", "Texto")
    entry
  end

  test "hostile search terms answer 200 and find the right entries, under Spanish and English" do
    HOSTILE_TERMS.each do |term|
      probe!(term)
      [ [ "es", "Sonda #{term}" ], [ "en", "Probe #{term}" ] ].each do |locale, title|
        I18n.with_locale(locale) do
          get "/changelog", params: { q: term }
          assert_response :ok, "#{term.inspect} under #{locale}"
          assert_includes titles, title, "#{term.inspect} under #{locale}"
          assert_not_includes titles, "Dark mode"
          assert_not_includes titles, "Modo oscuro"
        end
      end
    end
  end

  test "a hostile term that matches nothing returns nothing, and the injected condition does not run" do
    in_spanish do
      get "/changelog", params: { q: "x:pattern') OR 1=1 --" }
      assert_response :ok
      assert_empty titles
      get "/changelog", params: { q: "foo:bar" }
      assert_response :ok
      assert_empty titles
    end
  end

  test "the search SQL holds the escaped user text once per condition, never quoted again" do
    term = "zq'x:pattern"
    quoted = Shiplog::Entry.connection.quote("%#{term}%")
    [ "es", nil ].each do |locale|
      sql = Shiplog::Entry.search(term, locale:).to_sql
      assert_equal sql.scan("ILIKE").size, sql.scan(quoted).size, sql
      assert_not_includes sql.gsub(quoted, ""), "zq", sql # no second, re-quoted copy of the text
    end
  end

  # --- caching ---

  test "the ETag changes when a translation changes, on every page" do
    translation = translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")
    paths = %w[/roadmap /changelog /changelog/dark-mode /changelog.atom]
    before = paths.to_h { |path| [ path, in_spanish { get path; response.headers["ETag"] } ] }

    travel 1.minute do
      translation.update!(title: "Modo nocturno")
    end

    paths.each do |path|
      in_spanish { get path, headers: { "If-None-Match" => before[path] } }
      assert_response :ok, path
      assert_not_equal before[path], response.headers["ETag"], path
    end
  end

  test "the ETag differs between locales, and a translation that went stale no longer counts" do
    translation = translate!(@dark, "Modo oscuro", "Texto")
    english = (get "/changelog"; response.headers["ETag"])
    spanish = in_spanish { get "/changelog"; response.headers["ETag"] }
    assert_not_equal english, spanish

    translation.update_columns(source_digest: "older")
    stale = in_spanish { get "/changelog"; response.headers["ETag"] }
    assert_not_equal spanish, stale
  end

  test "an unchanged page answers 304 under the translated locale" do
    translate!(@dark, "Modo oscuro", "Texto")
    etag = in_spanish { get "/changelog"; response.headers["ETag"] }

    in_spanish { get "/changelog", headers: { "If-None-Match" => etag } }

    assert_response :not_modified
  end

  # --- queries ---

  def bulk_translated(count)
    now = Time.current
    rows = Array.new(count) do |i|
      { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: 40_000 + i, title: "Bulk #{i}", body: "Body #{i}",
        slug: "bulk-#{i}", released_on: Date.new(2026, 8, 1) - i, approved_at: now, created_at: now, updated_at: now }
    end
    ids = Shiplog::Entry.insert_all!(rows, returning: %w[id]).rows.flatten
    ids.each do |id|
      entry = Shiplog::Entry.find(id)
      translate!(entry, "Masivo #{id}", "Cuerpo #{id}")
    end
  end

  test "no page runs a query per entry under a translated locale" do
    translate!(@dark, "Modo oscuro", "Texto")
    queries = lambda do |path|
      in_spanish { count_queries { get path } }
    end
    paths = %w[/changelog /changelog.atom /changelog?q=o /roadmap /changelog/dark-mode]
    few = paths.to_h { |path| [ path, queries.(path) ] }

    bulk_translated(12)
    paths.each do |path|
      assert_equal few[path], queries.(path), "#{path} runs a query per translated entry"
    end
    in_spanish do
      get "/changelog"
      assert_includes titles.join, "Masivo"
    end
  end

  test "the roadmap runs no query per translated card" do
    few = in_spanish { count_queries { get "/roadmap" } }
    translate!(@roadmap, "Sube muchos", "Texto")
    translate!(shiplog_entries(:later_item_roadmap), "Más adelante", "Texto")
    translate!(@dark, "Modo oscuro", "Texto")

    assert_equal few, in_spanish { count_queries { get "/roadmap" } }, "one preload query for all cards and the shipped list"
  end

  test "English pages run no translation query at all" do
    translate!(@dark, "Modo oscuro", "Texto")

    statements = sql_statements { get "/changelog"; get "/roadmap"; get "/changelog.atom"; get "/changelog/dark-mode" }

    assert_empty statements.grep(/shiplog_entry_translations/)
  end

  # --- host routing (the dummy app serves /es/... with I18n.locale = :es, see config/initializers/locale_prefix.rb) ---

  test "the dummy host serves the pages under /es, with links that keep the prefix" do
    translate!(@dark, "Modo oscuro", "Cambia a un tema oscuro.")

    get "/es/changelog"

    assert_response :ok
    assert_select "html[lang=es]"
    assert_select ".shiplog-entry__title a[href=?]", "/es/changelog/dark-mode", text: "Modo oscuro"
    assert_select "nav.shiplog-switcher a", text: "Hoja de ruta"
  end
end
