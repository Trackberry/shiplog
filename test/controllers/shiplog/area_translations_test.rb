require "test_helper"
require "rexml/document"

# Area names under a translated locale: the filter pills, the tags, the permalink and the feed's category label.
class Shiplog::AreaTranslationsTest < ActionDispatch::IntegrationTest
  ATOM = "http://www.w3.org/2005/Atom".freeze

  setup do
    Shiplog.config.locales = [ :es ]
    @packing = Shiplog::Area.create!(name: "Packing Lists")
    @reports = Shiplog::Area.create!(name: "Reports")
    @packing.update_columns(name_translations: { "es" => "Listas de embalaje" })
    @reports.update_columns(name_translations: { "es" => "Informes" })
    @dark = shiplog_entries(:dark_mode_feature)
    @csv = shiplog_entries(:csv_change_draft)
    @csv.update!(status: "approved", released_on: Date.new(2026, 9, 15), approved_at: Time.utc(2026, 9, 15), slug: "better-csv-validation",
      body: "Files with unknown headers are rejected.")
    @dark.update!(area: @packing)
    @csv.update!(area: @reports)
  end

  def pills = css_select("nav.shiplog-areas a.shiplog-areas__link").map(&:text)

  test "the filter pills and entry tags show the translated names under /es, the links keep the English slug" do
    get "/es/changelog"

    assert_response :ok
    assert_equal [ "Todas", "Listas de embalaje", "Informes" ], pills
    assert_select "nav.shiplog-areas a[href=?]", "/es/changelog?area=packing-lists", text: "Listas de embalaje"
    assert_equal [ "Informes", "Listas de embalaje" ], css_select(".shiplog-entry__area").map(&:text).sort
  end

  test "English pages keep the English names" do
    get "/changelog"

    assert_equal [ "All", "Packing Lists", "Reports" ], pills
    assert_select ".shiplog-entry__area", text: "Packing Lists"
  end

  test "an area without a translation shows its English name under /es" do
    @reports.update_columns(name_translations: {})
    get "/es/changelog"

    assert_equal [ "Todas", "Listas de embalaje", "Reports" ], pills
  end

  test "a filtered page works under /es with the same slug" do
    get "/es/changelog", params: { area: "packing-lists" }

    assert_response :ok
    assert_select ".shiplog-areas__link--current", text: "Listas de embalaje"
  end

  test "the permalink tag is translated" do
    get "/es/changelog/#{@dark.slug}"

    assert_response :ok
    assert_select ".shiplog-entry__area", text: "Listas de embalaje"
  end

  test "the feed category keeps the slug as its term and translates the label" do
    get "/es/changelog.atom"

    assert_response :ok
    categories = REXML::Document.new(response.body).get_elements("//category").map { |c| [ c.attributes["term"], c.attributes["label"] ] }
    assert_includes categories, [ "packing-lists", "Listas de embalaje" ]
    assert_includes categories, [ "reports", "Informes" ]

    get "/changelog.atom"
    categories = REXML::Document.new(response.body).get_elements("//category").map { |c| [ c.attributes["term"], c.attributes["label"] ] }
    assert_includes categories, [ "packing-lists", "Packing Lists" ]
  end

  test "changing a translation changes the ETag of the list, the permalink and the feed" do
    paths = [ "/es/changelog", "/es/changelog/#{@dark.slug}", "/es/changelog.atom" ]
    etags = paths.map { |path| get(path) && response.headers["ETag"] }
    paths.zip(etags).each do |path, etag|
      get path, headers: { "If-None-Match" => etag }
      assert_response :not_modified, path
    end

    @packing.update!(name_translations: { "es" => "Listas de bultos" })

    paths.zip(etags).each do |path, etag|
      get path, headers: { "If-None-Match" => etag }
      assert_response :ok, path
    end
    get "/es/changelog"
    assert_equal "Listas de bultos", pills[1]
  end

  test "no translation_missing in the pages" do
    [ "/es/changelog", "/es/changelog/#{@dark.slug}", "/es/changelog.atom", "/changelog" ].each do |path|
      get path
      assert_no_match(/translation[ _]missing/i, response.body, path)
    end
  end
end
