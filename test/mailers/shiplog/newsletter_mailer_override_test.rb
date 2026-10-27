require "test_helper"

# A host's own announcement template: what the README's "Customising the email" promises it can use.
class Shiplog::NewsletterMailerOverrideTest < ActionMailer::TestCase
  OVERRIDES = Rails.root.join("../fixtures/files/views/newsletter_override")

  setup do
    enable_newsletter!
    @original_paths = Shiplog::NewsletterMailer.view_paths
    Shiplog::NewsletterMailer.prepend_view_path(OVERRIDES.to_s)
    @entry = approved_announcement
    @entry.update!(title: "October recap", body: "Intro.\n\n## Highlights\n\n### Dark mode\n\nDup.\n\n## Also improved\n\n- One.")
  end

  teardown { Shiplog::NewsletterMailer.view_paths = @original_paths }

  def mail = Shiplog::NewsletterMailer.announcement(@entry, "ana@example.com", locale: "en", unsubscribe_url: "https://example.com/u", preferences_url: "https://example.com/p")

  test "the override renders with the documented content, helpers and links, and the headers are still set" do
    html = mail.html_part.body.to_s

    assert_includes html, %(<h1 id="override">October recap (October 2026)</h1>)
    assert_includes html, %(<div id="intro"><p style=)
    assert_includes html, %(<h2><a href="https://example.com/changelog/dark-mode">Dark mode</a></h2>)
    assert_includes html, "<p>Switch to a dark theme.</p>"
    assert_includes html, %(<div id="rest"><h2 style=)
    assert_includes html, %(href="https://example.com/changelog")
    assert_includes html, %(<a href="https://example.com/u">Unsubscribe</a>)
    assert_includes html, %(<a href="https://example.com/p">Preferences</a>)
    assert_includes html, "<address>Acme Inc., 1 Main Street, Springfield</address>"
    assert_not_includes html, "Dup."
    assert_equal "<https://example.com/u>", mail["List-Unsubscribe"].to_s
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].to_s
    text = mail.text_part.body.to_s
    assert_includes text, "October recap (October 2026)"
    assert_includes text, "* Dark mode: https://example.com/changelog/dark-mode"
    assert_includes text, "Unsubscribe: https://example.com/u"
  end

  test "an override of the HTML part alone loses the text part: Rails takes a mailer's templates from the first path that has any" do
    Shiplog::NewsletterMailer.view_paths = @original_paths
    Shiplog::NewsletterMailer.prepend_view_path(Rails.root.join("../fixtures/files/views/newsletter_override_html_only").to_s)

    assert_not mail.multipart?
    assert_includes mail.body.to_s, %(<h1 id="override">)
  end

  test "the override sees the whole body when the split rule does not apply" do
    shiplog_entries(:dark_mode_feature).update_columns(slug: nil)

    html = mail.html_part.body.to_s

    assert_includes html, %(<div id="body">)
    assert_includes html, "Dup."
    assert_not_includes html, %(class="card")
  end

  test "the documented content interface is stable" do
    content = Shiplog::Newsletter::Content.new(@entry, "en")

    %i[title month preheader html highlights_shown? intro_html intro_text highlights rest_html rest_text text view_url changelog_url accent logo_url address product_name].each do |name|
      assert_respond_to content, name
    end
    highlight = content.highlights.first
    %i[title summary url image_url image_alt image_width image_height image?].each { |name| assert_respond_to highlight, name }
  end
end
