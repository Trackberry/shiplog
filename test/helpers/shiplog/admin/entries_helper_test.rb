require "test_helper"

class Shiplog::Admin::EntriesHelperTest < ActionView::TestCase
  include Shiplog::Admin::EntriesHelper

  test "newsletter_blocked_message spells out each blocker, with the missing locales" do
    with_stub(Shiplog::Newsletter, :missing_locales, ->(*) { [ :es, :fr ] }) do
      assert_equal "Sending is not possible yet: the announcement is not approved, a translation is missing or stale (es, fr).",
        newsletter_blocked_message(Object.new, [ :not_approved, :translations ])
    end
  end
end
