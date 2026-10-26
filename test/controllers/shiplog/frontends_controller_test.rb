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

  test "the stylesheets live in the shiplog layer and only style Shiplog classes" do
    dir = Rails.root.join("../../app/frontend/shiplog")
    %w[shiplog admin].each do |name|
      css = dir.join("#{name}.css").read.gsub(%r{/\*.*?\*/}m, "")
      assert_match(/\A\s*@layer shiplog \{/, css, name)
      selectors = css.scan(/^\s*([^\s@}][^{};\n]*?)\s*\{/).flatten.reject { |selector| selector.match?(/\A(\d+%|from|to)\z/) }
      selectors.flat_map { |list| list.split(",") }.map(&:strip).each do |selector|
        assert_match(/\A(\.shiplog-|body:has\(\.shiplog-)/, selector, "#{name}.css: #{selector}")
        assert_match(/\A\.shiplog-admin/, selector, "admin.css must be scoped: #{selector}") if name == "admin"
      end
    end
  end

  test "dark colours are only applied where Shiplog owns the page background" do
    dir = Rails.root.join("../../app/frontend/shiplog")
    { "shiplog" => ".shiplog-layout", "admin" => ".shiplog-admin--standalone" }.each do |name, owner|
      css = dir.join("#{name}.css").read.gsub(%r{/\*.*?\*/}m, "")
      dark = css[/@media \(prefers-color-scheme: dark\) \{(.*?)\n  \}/m, 1]
      assert dark.present?, "#{name}.css has a dark block"
      selectors = dark.scan(/^\s*([^\s}][^{};\n]*?)\s*\{/).flatten.flat_map { |list| list.split(",") }.map(&:strip)
      assert selectors.any?, name
      selectors.each { |selector| assert_includes selector, owner, "#{name}.css dark selector: #{selector}" }
    end
  end

  test "the host-safe defaults inherit the text colour and mix surfaces from currentColor" do
    dir = Rails.root.join("../../app/frontend/shiplog")
    assert_match(/--sl-fg: var\(--shiplog-fg, currentColor\)/, dir.join("shiplog.css").read)
    assert_match(/--sl-border: var\(--shiplog-border, color-mix\(in srgb, currentColor/, dir.join("shiplog.css").read)
    assert_match(/--sa-fg: var\(--shiplog-admin-fg, currentColor\)/, dir.join("admin.css").read)
  end

  test "admin variables are read through var() so :root can override them" do
    css = Rails.root.join("../../app/frontend/shiplog/admin.css").read
    %w[fg muted bg surface border accent].each do |name|
      assert_match(/--sa-#{name}: var\(--shiplog-admin-#{name}, /, css, name)
    end
    assert_no_match(/^\s*--shiplog-admin-[a-z]+:/, css)
  end

  test "a version other than the current one is not found" do
    get "/shiplog/assets/0.0.0-stale/shiplog.css"
    assert_response :not_found
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
