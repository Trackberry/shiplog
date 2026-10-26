require "test_helper"
require "open3"

# A host initializer (or gem) that loads ActionView::Base during boot runs the engine's on_load hook before the
# main autoloader exists. The hook must not need autoloading, or the app does not boot.
class EarlyActionViewBootTest < ActiveSupport::TestCase
  SCRIPT = File.expand_path("../support/boot_with_early_action_view.rb", __dir__)

  test "an app boots when an initializer loads ActionView::Base early, and shiplog_head_tags works" do
    output, error, status = Open3.capture3({ "BUNDLE_GEMFILE" => ENV["BUNDLE_GEMFILE"] }.compact, RbConfig.ruby, SCRIPT)

    assert status.success?, "the app did not boot:\n#{error}"
    report = JSON.parse(output.lines.last)
    assert_equal "Shiplog::HeadTagsHelper", report["helper_owner"]
    assert_equal "", report["host_page"]
    assert_equal 200, report["host_page_status"]
    # Only meaningful when loading is lazy: with eager_load (the dummy app on CI) every controller is loaded at boot.
    unless report["eager_load"]
      assert_equal false, report["public_controller_loaded_by_host_page"], "a host page loaded Shiplog::PublicController"
    end
    assert_equal 200, report["status"]
    assert_equal "http://example.org/changelog", report["canonical"]
  end
end
