require "test_helper"

class Shiplog::FrontendHelperTest < ActionView::TestCase
  include Shiplog::FrontendHelper

  def frontend_path(**options) = Shiplog::Engine.routes.url_helpers.frontend_path(**options)
  def content_security_policy_nonce = "abc123"

  test "stylesheet tag carries the nonce and the versioned path" do
    html = shiplog_stylesheet_tag("shiplog")
    assert_includes html, %(href="/shiplog/assets/#{Shiplog::VERSION}/shiplog.css")
    assert_includes html, %(rel="stylesheet")
    assert_includes html, %(nonce="abc123")
  end

  test "javascript tag is a module script with the nonce" do
    html = shiplog_javascript_tag("board")
    assert_includes html, %(src="/shiplog/assets/#{Shiplog::VERSION}/board.js")
    assert_includes html, %(type="module")
    assert_includes html, %(nonce="abc123")
  end
end
