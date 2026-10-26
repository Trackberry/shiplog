require "application_system_test_case"

class EntryImagesSystemTest < ApplicationSystemTestCase
  test "an image uploaded in the admin shows on the entry's permalink page" do
    entry = shiplog_entries(:dark_mode_feature)

    visit "/admin/shiplog/entries/#{entry.id}/edit"
    assert_selector "h2", text: "Screenshots"
    attach_file "images[]", file_fixture("images/pixel.png").to_s
    click_button "Upload images"

    assert_text "Image added."
    assert_selector ".shiplog-admin-images__item img[alt='Dark mode']"
    fill_in "alt", with: "The dark theme"
    click_button "Save alt text"
    assert_text "Alt text saved."

    visit "/changelog/dark-mode"
    assert_selector "article.shiplog-permalink img.shiplog-entry__image[alt='The dark theme'][loading=lazy]"
    # The image loads lazily and asynchronously: wait for it instead of reading `complete` once.
    page.document.synchronize(5) do
      loaded = evaluate_script("document.querySelector('img.shiplog-entry__image').complete && document.querySelector('img.shiplog-entry__image').naturalWidth")
      raise Capybara::ExpectationNotMet, "the image has not loaded (naturalWidth: #{loaded.inspect})" unless loaded == 1
    end
  end
end
