require "test_helper"

class Shiplog::Admin::TranslationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  ADMIN = "/admin/shiplog".freeze

  setup do
    Shiplog.config.locales = [ :es, :fr ]
    Shiplog.config.rewriter = ->(_prompt) { "{}" }
    @entry = shiplog_entries(:dark_mode_feature)
  end

  def translate!(locale: "es", title: "Modo oscuro", body: "Cambia a un tema oscuro.", **attributes)
    @entry.translations.create!(locale:, title:, body:, source_digest: @entry.translation_source_digest, **attributes)
  end

  def section(locale) = ".shiplog-translation[data-locale=#{locale}]"

  test "the edit page has no translations section without configured locales" do
    Shiplog.config.locales = []
    get "#{ADMIN}/entries/#{@entry.id}/edit"

    assert_response :ok
    assert_select ".shiplog-translations", 0
  end

  test "the edit page shows a section per locale with the title and body, editable" do
    translate!
    get "#{ADMIN}/entries/#{@entry.id}/edit"

    assert_select ".shiplog-translations h2", text: "Translations"
    assert_select "#{section(:es)} form[action=?][method=post]", "#{ADMIN}/entries/#{@entry.id}/translations/es" do
      assert_select "input[name='translation[title]'][value=?]", "Modo oscuro"
      assert_select "textarea[name='translation[body]']", text: "Cambia a un tema oscuro."
      assert_select "input[type=submit][value=?]", "Save"
    end
    assert_select section(:es) + " .shiplog-badge", text: "Up to date"
    assert_select section(:fr), 1
  end

  test "a locale without a translation is marked missing, and its form is empty" do
    get "#{ADMIN}/entries/#{@entry.id}/edit"

    assert_select "#{section(:es)} .shiplog-badge", text: "Missing"
    assert_select "#{section(:es)} input[name='translation[title]']:not([value])"
  end

  test "a translation made from older English text is marked stale" do
    translate!.update_columns(source_digest: "older")
    get "#{ADMIN}/entries/#{@entry.id}/edit"

    assert_select "#{section(:es)} .shiplog-badge", text: "Stale"
  end

  test "an admin-edited translation is marked edited" do
    translate!(edited_by_admin: true)
    get "#{ADMIN}/entries/#{@entry.id}/edit"

    assert_select "#{section(:es)} .shiplog-badge", text: "Edited by an admin"
  end

  test "each section has a Retranslate button, keeping the inbox filters" do
    get "#{ADMIN}/entries/#{@entry.id}/edit", params: { status: "approved", page: 2 }

    assert_select "#{section(:es)} form[action=?]", "#{ADMIN}/entries/#{@entry.id}/translations/es/retranslation?page=2&status=approved" do
      assert_select "button", text: "Retranslate"
    end
    assert_select "#{section(:es)} form[action=?]", "#{ADMIN}/entries/#{@entry.id}/translations/es?page=2&status=approved"
  end

  test "a draft shows that translations are written on approval and offers no Retranslate" do
    draft = shiplog_entries(:csv_change_draft)
    get "#{ADMIN}/entries/#{draft.id}/edit"

    assert_select ".shiplog-translations"
    assert_select ".shiplog-translations button", text: "Retranslate", count: 0
  end

  test "saving stores the text, marks it edited and current, and keeps the inbox filters" do
    patch "#{ADMIN}/entries/#{@entry.id}/translations/es", params: { translation: { title: "Modo noche", body: "Un tema oscuro." }, status: "approved", page: 2 }

    assert_redirected_to "#{ADMIN}/entries/#{@entry.id}/edit?page=2&status=approved"
    translation = @entry.translations.find_by!(locale: "es")
    assert_equal "Modo noche", translation.title
    assert_equal "Un tema oscuro.", translation.body
    assert translation.edited_by_admin
    assert_equal @entry.translation_source_digest, translation.source_digest
    assert_not translation.stale?
    follow_redirect!
    assert_select ".shiplog-admin__flash", text: /Translation saved/
    assert_no_enqueued_jobs only: Shiplog::TranslateEntryJob
  end

  test "saving a stale translation makes it current and edited" do
    translate!.update_columns(source_digest: "older")

    patch "#{ADMIN}/entries/#{@entry.id}/translations/es", params: { translation: { title: "Modo oscuro 2", body: "Texto" } }

    translation = @entry.translations.find_by!(locale: "es")
    assert_not translation.stale?
    assert translation.edited_by_admin
  end

  test "a blank title is refused and nothing changes" do
    translate!

    patch "#{ADMIN}/entries/#{@entry.id}/translations/es", params: { translation: { title: " ", body: "x" } }

    assert_redirected_to "#{ADMIN}/entries/#{@entry.id}/edit"
    follow_redirect!
    assert_select ".shiplog-admin__flash--alert", text: /Title/
    assert_equal "Modo oscuro", @entry.translations.find_by!(locale: "es").title
    assert_not @entry.translations.find_by!(locale: "es").edited_by_admin
  end

  test "a locale that is not configured is not found" do
    patch "#{ADMIN}/entries/#{@entry.id}/translations/de", params: { translation: { title: "x", body: "y" } }
    assert_response :not_found
    post "#{ADMIN}/entries/#{@entry.id}/translations/de/retranslation"
    assert_response :not_found
    assert_equal 0, @entry.translations.count
  end

  test "the edit form does not take the translation's digest or flag" do
    patch "#{ADMIN}/entries/#{@entry.id}/translations/es", params: { translation: { title: "x", body: "y", source_digest: "forged", edited_by_admin: "0", locale: "fr" } }

    translation = @entry.translations.find_by!(locale: "es")
    assert_equal @entry.translation_source_digest, translation.source_digest
    assert translation.edited_by_admin
    assert_equal 0, @entry.translations.where(locale: "fr").count
  end

  test "Retranslate enqueues a forced job for the locale and keeps the inbox filters" do
    translate!(edited_by_admin: true)

    assert_enqueued_with(job: Shiplog::TranslateEntryJob, args: [ @entry, :es, { force: true } ]) do
      post "#{ADMIN}/entries/#{@entry.id}/translations/es/retranslation", params: { status: "approved" }
    end

    assert_redirected_to "#{ADMIN}/entries/#{@entry.id}/edit?status=approved"
    follow_redirect!
    assert_select ".shiplog-admin__flash", text: /Translation queued/
    assert_enqueued_jobs 1, only: Shiplog::TranslateEntryJob
  end

  test "Retranslate on an entry that is not approved enqueues nothing" do
    draft = shiplog_entries(:csv_change_draft)

    assert_no_enqueued_jobs only: Shiplog::TranslateEntryJob do
      post "#{ADMIN}/entries/#{draft.id}/translations/es/retranslation"
    end
    assert_redirected_to "#{ADMIN}/entries/#{draft.id}/edit"
    follow_redirect!
    assert_select ".shiplog-admin__flash--alert", text: /only approved entries/i
  end

  test "Retranslate without a rewriter enqueues nothing" do
    Shiplog.config.rewriter = nil

    assert_no_enqueued_jobs only: Shiplog::TranslateEntryJob do
      post "#{ADMIN}/entries/#{@entry.id}/translations/es/retranslation"
    end
    follow_redirect!
    assert_select ".shiplog-admin__flash--alert", text: /rewriter/
  end

  test "saving the English text of an approved entry enqueues a translation per locale" do
    assert_enqueued_jobs 2, only: Shiplog::TranslateEntryJob do
      patch "#{ADMIN}/entries/#{@entry.id}", params: { entry: { title: "Dark mode for all", body: @entry.body } }
    end
  end

  test "approving enqueues a translation per locale" do
    draft = shiplog_entries(:csv_change_draft)

    assert_enqueued_jobs 2, only: Shiplog::TranslateEntryJob do
      post "#{ADMIN}/entries/#{draft.id}/approval"
    end
  end

  test "the admin renders and saves for a locale outside available_locales under a host that switches locale from params[:locale]" do
    assert_not_includes I18n.available_locales, :fr
    @entry.translations.create!(locale: "fr", title: "Mode sombre", body: "Texte", source_digest: @entry.translation_source_digest)

    get "#{ADMIN}/entries/#{@entry.id}/edit"
    assert_response :ok
    assert_select "#{section(:fr)} form[action=?]", "#{ADMIN}/entries/#{@entry.id}/translations/fr"

    patch "#{ADMIN}/entries/#{@entry.id}/translations/fr", params: { translation: { title: "Mode nuit", body: "Un thème sombre." } }
    assert_redirected_to "#{ADMIN}/entries/#{@entry.id}/edit"
    assert_equal "Mode nuit", @entry.translations.find_by!(locale: "fr").title

    assert_enqueued_with(job: Shiplog::TranslateEntryJob, args: [ @entry, :fr, { force: true } ]) do
      post "#{ADMIN}/entries/#{@entry.id}/translations/fr/retranslation"
    end
  end

  test "the locale in the URL is not params[:locale]" do
    patch "#{ADMIN}/entries/#{@entry.id}/translations/es", params: { translation: { title: "x", body: "y" } }

    assert_equal "es", request.path_parameters[:translation_locale]
    assert_nil request.path_parameters[:locale]
  end

  test "requires the admin to be authorized" do
    Shiplog.config.authorize_admin = ->(_controller) { false }

    patch "#{ADMIN}/entries/#{@entry.id}/translations/es", params: { translation: { title: "x", body: "y" } }
    assert_response :forbidden
    post "#{ADMIN}/entries/#{@entry.id}/translations/es/retranslation"
    assert_response :forbidden
  end
end
