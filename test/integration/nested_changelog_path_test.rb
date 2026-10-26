require "test_helper"

# config.changelog_path may have several segments ("docs/whats_new"); the routes are drawn from it when they load.
class NestedChangelogPathTest < ActionDispatch::IntegrationTest
  def redraw_engine_routes
    Shiplog::Engine.routes.clear!
    load Shiplog::Engine.root.join("config/routes.rb")
  end

  setup do
    Shiplog.config.changelog_path = "/docs/whats_new/"
    redraw_engine_routes
  end

  teardown do
    Shiplog.reset_config!
    redraw_engine_routes
  end

  test "the list, the feed and the permalinks live below a nested path" do
    assert_equal "/docs/whats_new", Shiplog::Engine.routes.url_helpers.changelog_path

    get "/docs/whats_new"
    assert_response :ok
    assert_select "form[role=search][action=?]", "/docs/whats_new"
    get "/docs/whats_new.atom"
    assert_response :ok
    get "/docs/whats_new/dark-mode"
    assert_response :ok
    get "/changelog"
    assert_response :not_found
  end
end
