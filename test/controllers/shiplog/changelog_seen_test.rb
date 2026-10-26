require "test_helper"

class Shiplog::ChangelogSeenTest < ActionDispatch::IntegrationTest
  test "it defaults to nil and the pages work without it" do
    assert_nil Shiplog.config.on_changelog_seen
    get "/changelog"
    assert_response :ok
  end

  test "it is called with the controller on the changelog index" do
    seen = []
    Shiplog.config.on_changelog_seen = ->(controller) { seen << controller }
    get "/changelog"
    assert_equal 1, seen.size
    assert_kind_of Shiplog::ChangelogsController, seen.first
  end

  test "a revisit answered with 304 still counts as seen" do
    seen = 0
    Shiplog.config.on_changelog_seen = ->(_controller) { seen += 1 }
    get "/changelog"
    get "/changelog", headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
    assert_equal 2, seen
  end

  test "a revisit of a permalink answered with 304 still counts as seen" do
    seen = 0
    Shiplog.config.on_changelog_seen = ->(_controller) { seen += 1 }
    get "/changelog/dark-mode"
    get "/changelog/dark-mode", headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
    assert_equal 2, seen
  end

  test "it runs before the layout renders, so a navbar badge in the same response sees what it set" do
    Shiplog.config.public_layout = "seen_badge"
    Shiplog.config.on_changelog_seen = ->(controller) { controller.instance_variable_set(:@seen_badge, "badge-after-callback") }

    get "/changelog"
    assert_select "#host-badge", text: "badge-after-callback"

    get "/changelog/dark-mode"
    assert_select "#host-badge", text: "badge-after-callback"
  end

  test "it does not run for an unknown permalink, a past-the-end page or the feed" do
    called = 0
    Shiplog.config.on_changelog_seen = ->(_controller) { called += 1 }
    get "/changelog/nope"
    assert_response :not_found
    get "/changelog.atom"
    assert_response :ok
    get "/changelog", params: { page: 99 }
    assert_response :not_found
    assert_equal 0, called
  end

  test "it runs on a permalink page" do
    seen = []
    Shiplog.config.on_changelog_seen = ->(controller) { seen << controller.class }
    get "/changelog/dark-mode"
    assert_equal [ Shiplog::ChangelogEntriesController ], seen
  end

  test "a page past the last one (404) does not count" do
    called = false
    Shiplog.config.on_changelog_seen = ->(_controller) { called = true }
    get "/changelog", params: { page: 99 }
    assert_response :not_found
    assert_not called
  end

  test "the roadmap does not call it" do
    called = false
    Shiplog.config.on_changelog_seen = ->(_controller) { called = true }
    get "/roadmap"
    assert_not called
  end

  test "the callback can stamp the response, because the response is not sent yet" do
    Shiplog.config.on_changelog_seen = ->(controller) { controller.response.set_header("X-Seen", "1") }
    get "/changelog"
    assert_equal "1", response.headers["X-Seen"]
  end

  test "a failing callback is logged and does not break the page" do
    Shiplog.config.on_changelog_seen = ->(_controller) { raise "boom" }
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    get "/changelog"
    assert_response :ok
    assert_match(/on_changelog_seen failed: RuntimeError: boom/, log.string)
    assert_match(/changelog_seen_test\.rb:\d+/, log.string, "the first lines of the backtrace are logged")
  ensure
    Rails.logger = original
  end

  test "it must be nil or callable" do
    assert_raises(ArgumentError) { Shiplog.config.on_changelog_seen = "nope" }
    Shiplog.config.on_changelog_seen = nil
  end
end
