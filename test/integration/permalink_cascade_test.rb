require "test_helper"

# The engine is mounted at "/", so /changelog/:slug could shadow host routes below the changelog path. An unknown
# slug answers 404 with X-Cascade: pass, which lets the host router go on to its later routes.
class PermalinkCascadeTest < ActionDispatch::IntegrationTest
  test "a host route declared after the mount still answers below the changelog path" do
    get "/changelog/archive"
    assert_response :ok
    assert_includes response.body, "News"
  end

  test "an unknown slug that no host route matches is a 404 for the whole app" do
    get "/changelog/nope"
    assert_response :not_found
  end

  test "the engine itself marks an unknown permalink with X-Cascade: pass" do
    app = Shiplog::Engine
    env = Rack::MockRequest.env_for("/changelog/archive")
    status, headers, = app.call(env)
    assert_equal 404, status
    assert_equal "pass", headers.find { |name, _| name.casecmp?("x-cascade") }&.last
  end

  test "a draft entry's slug cascades too, and a published one is still served by the engine" do
    shiplog_entries(:dark_mode_feature).update_columns(status: "draft")
    get "/changelog/dark-mode"
    assert_response :not_found
    shiplog_entries(:dark_mode_feature).update_columns(status: "approved")
    get "/changelog/dark-mode"
    assert_response :ok
  end
end
