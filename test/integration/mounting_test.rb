require "test_helper"

class MountingTest < ActionDispatch::IntegrationTest
  test "public engine mounted at root exposes roadmap and changelog paths" do
    assert_equal "/roadmap", Shiplog::Engine.routes.url_helpers.roadmap_path
    assert_equal "/changelog", Shiplog::Engine.routes.url_helpers.changelog_path
  end

  test "admin engine is a separate mount" do
    assert_equal "/admin/shiplog/", shiplog_admin.root_path
  end

  test "public and admin routes respond" do
    get "/roadmap"
    assert_response :ok
    get "/admin/shiplog/"
    assert_response :ok
  end
end
