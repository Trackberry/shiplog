require "test_helper"

# Every locale file Shiplog ships (config/locales/*.yml other than en.yml) must translate every shiplog.* key of
# en.yml, keep its plural forms and placeholders, and render without translation-missing.
class Shiplog::LocalesTest < ActiveSupport::TestCase
  LOCALES = Dir[Shiplog::Engine.root.join("config/locales/*.yml")].map { |path| File.basename(path, ".yml") }.sort - [ "en" ]

  def leaf_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? leaf_keys(value, path) : [ path ]
    end
  end

  def load_yaml(name) = YAML.load_file(Shiplog::Engine.root.join("config/locales/#{name}.yml"))

  def shiplog_keys(locale) = leaf_keys(load_yaml(locale).fetch(locale).fetch("shiplog")).sort

  def plural?(value) = value.is_a?(Hash) && value.key?("other")

  test "Shiplog ships es, de and nl" do
    assert_equal %w[de es nl], LOCALES
  end

  LOCALES.each do |locale|
    test "#{locale}.yml has every shiplog key of en.yml, public and admin" do
      english = shiplog_keys("en")
      translated = shiplog_keys(locale)

      assert_empty english - translated, "keys missing from #{locale}.yml"
      assert_empty translated - english, "keys in #{locale}.yml that en.yml lacks"
    end

    test "plural keys of #{locale}.yml have the same forms as English" do
      english = load_yaml("en").fetch("en").fetch("shiplog")
      translated = load_yaml(locale).fetch(locale).fetch("shiplog")
      plural_paths = ->(hash, prefix = []) do
        hash.flat_map do |key, value|
          next [] unless value.is_a?(Hash)

          plural?(value) ? [ prefix + [ key ] ] : plural_paths.(value, prefix + [ key ])
        end
      end

      assert_not_empty plural_paths.(english)
      plural_paths.(english).each do |keys|
        forms = translated.dig(*keys)
        assert_kind_of Hash, forms, keys.join(".")
        assert_equal english.dig(*keys).keys.sort, forms.keys.sort, keys.join(".")
      end
    end

    test "every placeholder of an English text is in its #{locale} text" do
      english = load_yaml("en").fetch("en").fetch("shiplog")
      translated = load_yaml(locale).fetch(locale).fetch("shiplog")
      placeholder = /%\{(\w+)\}/

      leaf_keys(english).each do |path|
        keys = path.split(".")
        source = english.dig(*keys)
        text = translated.dig(*keys)
        next unless source.is_a?(String) && text.is_a?(String)

        assert_equal source.scan(placeholder).flatten.sort, text.scan(placeholder).flatten.sort, "placeholders of #{path} in #{locale}.yml"
      end
    end

    test "#{locale}.yml names all twelve months" do
      names = load_yaml(locale).dig(locale, "date", "month_names")
      assert_equal 13, names.size
      assert_nil names.first
      assert names.drop(1).all?(&:present?)
    end

    test "#{locale} is an available locale" do
      assert_includes I18n.available_locales, locale.to_sym
    end
  end

  test "the Spanish texts are really translated and render without translation-missing" do
    I18n.with_locale(:es) do
      assert_equal "Hoja de ruta", I18n.t("shiplog.roadmap.title")
      assert_equal "1 resultado para “csv”", I18n.t("shiplog.changelog.search.summary", count: 1, query: "csv")
      assert_equal "Incluye 3 partes", I18n.t("shiplog.roadmap.parts", count: 3)
      assert_equal "1 de octubre de 2026", I18n.l(Date.new(2026, 10, 1), format: I18n.t("shiplog.date_format"))
    end
  end

  test "the German texts are really translated and render without translation-missing" do
    I18n.with_locale(:de) do
      assert_equal "Roadmap", I18n.t("shiplog.roadmap.title")
      assert_equal "Neuigkeiten", I18n.t("shiplog.changelog.title")
      assert_equal "1 Ergebnis für „csv“", I18n.t("shiplog.changelog.search.summary", count: 1, query: "csv")
      assert_equal "Umfasst 3 Teile", I18n.t("shiplog.roadmap.parts", count: 3)
      assert_equal "1. Oktober 2026", I18n.l(Date.new(2026, 10, 1), format: I18n.t("shiplog.date_format"))
      assert_equal "März 2026", Shiplog::Period.month_name(Date.new(2026, 3, 1), locale: :de)
    end
  end

  test "the Dutch texts are really translated and render without translation-missing" do
    I18n.with_locale(:nl) do
      assert_equal "Roadmap", I18n.t("shiplog.roadmap.title")
      assert_equal "1 resultaat voor “csv”", I18n.t("shiplog.changelog.search.summary", count: 1, query: "csv")
      assert_equal "Bestaat uit 3 onderdelen", I18n.t("shiplog.roadmap.parts", count: 3)
      assert_equal "1 oktober 2026", I18n.l(Date.new(2026, 10, 1), format: I18n.t("shiplog.date_format"))
      assert_equal "maart 2026", Shiplog::Period.month_name(Date.new(2026, 3, 1), locale: :nl)
    end
  end

  test "the translator names German and Dutch in its prompts" do
    assert_equal "German", Shiplog::Translator.language_name(:de)
    assert_equal "Dutch", Shiplog::Translator.language_name("nl")
  end
end
