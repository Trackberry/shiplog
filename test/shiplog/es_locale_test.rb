require "test_helper"

class Shiplog::EsLocaleTest < ActiveSupport::TestCase
  def leaf_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? leaf_keys(value, path) : [ path ]
    end
  end

  def load_yaml(name) = YAML.load_file(Shiplog::Engine.root.join("config/locales/#{name}.yml"))

  def shiplog_keys(locale) = leaf_keys(load_yaml(locale).fetch(locale).fetch("shiplog")).sort

  test "es.yml has every shiplog key of en.yml, public and admin" do
    english = shiplog_keys("en")
    spanish = shiplog_keys("es")

    assert_empty english - spanish, "keys missing from es.yml"
    assert_empty spanish - english, "keys in es.yml that en.yml lacks"
  end

  test "plural keys of es.yml have the same forms as English" do
    %w[shiplog.roadmap.parts shiplog.changelog.search.summary shiplog.admin.entries.images.added].each do |key|
      forms = ->(name) { load_yaml(name).dig(name, *key.split(".")) }
      assert_kind_of Hash, forms.("es"), key
      assert_equal forms.("en").keys.sort, forms.("es").keys.sort, key
    end
  end

  test "every placeholder of an English text is in its Spanish text" do
    english = load_yaml("en").fetch("en").fetch("shiplog")
    spanish = load_yaml("es").fetch("es").fetch("shiplog")
    placeholder = /%\{(\w+)\}/

    leaf_keys(english).each do |path|
      keys = path.split(".")
      source = english.dig(*keys)
      translated = spanish.dig(*keys)
      next unless source.is_a?(String) && translated.is_a?(String)

      assert_equal source.scan(placeholder).flatten.sort, translated.scan(placeholder).flatten.sort, "placeholders of #{path}"
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

  test "es is an available locale" do
    assert_includes I18n.available_locales, :es
  end
end
