require "test_helper"

class Shiplog::FrontendsControllerTest < ActionDispatch::IntegrationTest
  VERSION = Shiplog::VERSION

  test "serves the public stylesheet with long-lived caching" do
    get "/shiplog/assets/#{VERSION}/shiplog.css"
    assert_response :ok
    assert_equal "text/css", response.media_type
    cache_control = response.headers["Cache-Control"]
    assert_includes cache_control, "public"
    assert_includes cache_control, "max-age=#{1.year.to_i}"
    assert_includes cache_control, "immutable"
    assert_equal Rails.root.join("../../app/frontend/shiplog/shiplog.css").read, response.body
  end

  test "serves the board module as javascript" do
    get "/shiplog/assets/#{VERSION}/board.js"
    assert_response :ok
    assert_equal "text/javascript", response.media_type
  end

  test "the admin engine serves the same assets" do
    get "/admin/shiplog/assets/#{VERSION}/admin.css"
    assert_response :ok
    assert_equal "text/css", response.media_type
    assert_includes response.headers["Cache-Control"], "immutable"
  end

  test "an unknown name is not found" do
    get "/shiplog/assets/#{VERSION}/nope.css"
    assert_response :not_found
  end

  test "path traversal is not found" do
    get "/shiplog/assets/#{VERSION}/..%2F..%2Fshiplog.gemspec"
    assert_response :not_found
    get "/shiplog/assets/#{VERSION}/..%2Flib%2Fshiplog.rb"
    assert_response :not_found
  end

  test "the asset path embeds the gem version" do
    assert_equal "/shiplog/assets/#{VERSION}/shiplog.css",
      Shiplog::Engine.routes.url_helpers.frontend_path(version: VERSION, name: "shiplog.css")
  end
end
