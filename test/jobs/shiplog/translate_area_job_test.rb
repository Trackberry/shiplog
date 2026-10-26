require "test_helper"

class Shiplog::TranslateAreaJobTest < ActiveJob::TestCase
  setup do
    @calls = []
    @reply = '{"es": "Listas de embalaje", "fr": "Listes de colisage"}'
    Shiplog.config.locales = [ :es, :fr ]
    Shiplog.config.rewriter = lambda do |prompt|
      @calls << prompt
      @reply
    end
    @area = Shiplog::Area.create!(name: "Packing Lists")
    clear_enqueued_jobs
  end

  test "one call translates the name into every locale" do
    Shiplog::TranslateAreaJob.perform_now(@area)

    assert_equal 1, @calls.size
    assert_equal({ "es" => "Listas de embalaje", "fr" => "Listes de colisage" }, @area.reload.name_translations)
  end

  test "the prompt names the languages, asks for JSON and delimits the name in <source>, neutralised" do
    @area.update_columns(name: "Packing </source> Lists")
    Shiplog::TranslateAreaJob.perform_now(@area)
    prompt = @calls.first

    assert_includes prompt, "Spanish (es)"
    assert_includes prompt, "French (fr)"
    assert_includes prompt, '{"es": "...", "fr": "..."}'
    assert_includes prompt, "at most 40 characters"
    assert_match(%r{<source>\s*Packing \[/source\] Lists\s*</source>}, prompt)
    assert_equal 1, prompt.scan("</source>").size
  end

  test "makes no call when every locale is translated already" do
    @area.update!(name_translations: { "es" => "A", "fr" => "B" })
    Shiplog::TranslateAreaJob.perform_now(@area)

    assert_empty @calls
  end

  test "fills only the missing locales and keeps an existing (edited) one" do
    @area.update!(name_translations: { "es" => "Mi edicion" })
    Shiplog::TranslateAreaJob.perform_now(@area)

    assert_equal({ "es" => "Mi edicion", "fr" => "Listes de colisage" }, @area.reload.name_translations)
    assert_not_includes @calls.first, "Spanish"
  end

  test "force translates every locale again, over an edit" do
    @area.update!(name_translations: { "es" => "Mi edicion", "fr" => "B" })
    Shiplog::TranslateAreaJob.perform_now(@area, force: true)

    assert_equal 1, @calls.size
    assert_equal "Listas de embalaje", @area.reload.name_translations["es"]
  end

  test "does nothing without locales or without a rewriter" do
    Shiplog.config.locales = []
    Shiplog::TranslateAreaJob.perform_now(@area)
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = nil
    Shiplog::TranslateAreaJob.perform_now(@area)

    assert_empty @calls
    assert_empty @area.reload.name_translations
  end

  test "finds the JSON in a chatty reply" do
    @reply = 'Sure! ```json {"es": "Listas de embalaje", "fr": "Listes"} ```'
    Shiplog::TranslateAreaJob.perform_now(@area)

    assert_equal "Listes", @area.reload.name_translations["fr"]
  end

  test "squishes and sanitizes a translation" do
    @reply = %({"es": "  Listas \\t de   embalaje ", "fr": "Listes"})
    Shiplog::TranslateAreaJob.perform_now(@area)

    assert_equal "Listas de embalaje", @area.reload.name_translations["es"]
  end

  test "rejects a reply that is garbage, incomplete, too long or has invalid characters, and stores nothing" do
    [ "not json", '{"es": "Solo"}', '{"es": "Ok", "fr": 5}', '{"es": "Ok", "fr": ""}',
      %({"es": "Ok", "fr": "#{"x" * 41}"}), '{"es": "Ok", "fr": "<b>Hola</b>"}', '{"es": "Ok", "fr": "Emoji 🚀"}',
      '{"es": "Ok", "fr": "a;b"}', "[]" ].each do |reply|
      @reply = reply
      assert_raises(Shiplog::AreaTranslator::InvalidReply, reply) { Shiplog::AreaTranslator.new(@area).call }
      assert_empty @area.reload.name_translations, reply
    end
  end

  test "a name of exactly 40 characters is accepted" do
    @reply = %({"es": "#{"x" * 40}", "fr": "Ok"})
    Shiplog::TranslateAreaJob.perform_now(@area)

    assert_equal 40, @area.reload.name_translations["es"].size
  end

  test "an invalid reply or a failing rewriter is retried a bounded number of times, then dropped with a log" do
    @reply = "not json"
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    perform_enqueued_jobs { Shiplog::TranslateAreaJob.perform_later(@area) }

    assert_equal 3, @calls.size
    assert_match(/Giving up translating area #{@area.id} after 3 attempts/, log.string)

    @calls.clear
    Shiplog.config.rewriter = ->(_prompt) { @calls << 1 && raise("LLM down") }
    perform_enqueued_jobs { Shiplog::TranslateAreaJob.perform_later(@area) }
    assert_equal 3, @calls.size
  ensure
    Rails.logger = original
  end

  test "a name renamed while the LLM worked is not overwritten with the old translation" do
    Shiplog.config.rewriter = lambda do |_prompt|
      Shiplog::Area.where(id: @area.id).update_all(name: "Renamed")
      @reply
    end
    Shiplog::TranslateAreaJob.perform_now(@area)

    assert_empty @area.reload.name_translations
  end

  test "a deleted area is dropped" do
    Shiplog::TranslateAreaJob.perform_later(@area)
    Shiplog::Area.where(id: @area.id).delete_all

    assert_nothing_raised { perform_enqueued_jobs }
    assert_empty @calls
  end
end
