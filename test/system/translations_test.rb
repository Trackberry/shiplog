require "application_system_test_case"

# Approving an entry translates it with the host's rewriter, and the changelog under the /es prefix of the dummy
# host (see test/dummy/config/initializers/locale_prefix.rb) shows the Spanish title; /changelog stays English.
class TranslationsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "an approved entry shows its Spanish title on the Spanish changelog" do
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = ->(_prompt) { '{"title":"Mejor validación de CSV","body":"Los archivos con cabeceras desconocidas ahora se rechazan."}' }
    entry = shiplog_entries(:csv_change_draft)

    perform_enqueued_jobs { entry.approve!(by: "ed@example.com") }

    visit "/es/changelog"
    assert_selector "html[lang=es]"
    assert_selector ".shiplog-entry__title", text: "Mejor validación de CSV"
    assert_selector ".shiplog-entry__body", text: "cabeceras desconocidas"
    assert_selector ".shiplog-entry__title", text: "Dark mode" # not translated yet: English

    click_link "Mejor validación de CSV"
    assert_current_path "/es/changelog/#{entry.reload.slug}"
    assert_selector "article.shiplog-permalink .shiplog-entry__title", text: "Mejor validación de CSV"

    visit "/changelog"
    assert_selector ".shiplog-entry__title", text: "Better CSV validation"
    assert_no_selector ".shiplog-entry__title", text: "Mejor validación de CSV"
  end
end
