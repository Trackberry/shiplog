require "test_helper"

class Shiplog::ConfigurationTest < ActiveSupport::TestCase
  test "admin access is denied by default" do
    assert_not Shiplog::Configuration.new.authorize_admin.call(Object.new)
  end

  test "defaults" do
    config = Shiplog.config
    assert_equal "public", config.public_label
    assert_equal %w[soon], config.soon_labels
    assert_equal %w[feat fix perf], config.commit_types
    assert_equal "roadmap", config.roadmap_path
    assert_equal "changelog", config.changelog_path
    assert_equal "ActionController::Base", config.public_parent_controller
    assert_equal "ActionController::Base", config.admin_parent_controller
    assert_equal "shiplog/admin", config.admin_layout
    assert_equal({}, config.classes)
    assert_equal true, config.stylesheet
    assert_equal :standalone, config.admin_chrome
    assert_equal true, config.admin_flash
    assert_not config.authorize_admin.call(Object.new)
    assert_equal [], config.extra_pages
    assert_equal({}, config.repository_labels)
    assert_equal 4, config.roadmap_shipped_count
    assert_nil config.feedback_path
  end

  test "extra_pages accepts Strings and callables for label and path, and string keys" do
    config = Shiplog::Configuration.new
    config.extra_pages = [ { label: "News", path: "/learn/news" }, { "label" => -> { "Docs" }, "path" => -> { "/docs" } } ]

    assert_equal %i[label path], config.extra_pages.first.keys
    assert_equal %i[label path], config.extra_pages.last.keys
    assert config.extra_pages.frozen?
    config.extra_pages = nil
    assert_equal [], config.extra_pages
  end

  test "extra_pages rejects anything but an Array of { label:, path: } Hashes" do
    config = Shiplog::Configuration.new
    [ "News", [ "News" ], [ { label: "News" } ], [ { label: "News", path: "/n", extra: 1 } ],
      [ { label: 1, path: "/n" } ], [ { label: "News", path: nil } ], [ { label: "", path: "/n" } ] ].each do |value|
      assert_raises(ArgumentError, "expected #{value.inspect} to raise") { config.extra_pages = value }
    end
    assert_equal [], config.extra_pages
  end

  test "repository_labels accepts a Hash of Strings and callables" do
    config = Shiplog::Configuration.new
    config.repository_labels = { "Acme/ios" => "iPhone", "Acme/android" => -> { "Android" } }
    assert_equal "iPhone", config.repository_labels["Acme/ios"]
    config.repository_labels = nil
    assert_equal({}, config.repository_labels)
    assert_raises(ArgumentError) { config.repository_labels = [ "Acme/ios" ] }
    assert_raises(ArgumentError) { config.repository_labels = { "Acme/ios" => 1 } }
  end

  test "roadmap_shipped_count must be a non-negative Integer" do
    config = Shiplog::Configuration.new
    config.roadmap_shipped_count = 0
    assert_equal 0, config.roadmap_shipped_count
    [ -1, "4", nil, 1.5 ].each { |value| assert_raises(ArgumentError) { config.roadmap_shipped_count = value } }
  end

  test "github_token accepts a string or a callable" do
    Shiplog.configure { |c| c.github_token = "abc" }
    assert_equal "abc", Shiplog.config.resolved_github_token
    Shiplog.configure { |c| c.github_token = -> { "xyz" } }
    assert_equal "xyz", Shiplog.config.resolved_github_token
  end

  test "excluded_author? matches strings and regexps" do
    Shiplog.configure { |c| c.excluded_authors = [ "robot", /\[bot\]\z/ ] }
    assert Shiplog.config.excluded_author?("dependabot[bot]")
    assert Shiplog.config.excluded_author?("robot")
    refute Shiplog.config.excluded_author?("edouard")
  end

  test "repository_configured? returns the configured spelling case-insensitively" do
    config = Shiplog::Configuration.new
    config.repositories = [ "Acme/Widgets" ]
    assert_equal "Acme/Widgets", config.repository_configured?("acme/widgets")
    assert_nil config.repository_configured?("acme/other")
    assert_nil config.repository_configured?(nil)
  end

  test "repositories accepts Strings and Hashes with per-repository options" do
    config = Shiplog::Configuration.new
    config.repositories = [
      "Acme/app",
      { name: "Acme/market_data", changelog: false, gem: "market_data" },
      { "name" => "Acme/produce", "gem" => "acme-produce" }
    ]

    assert_equal %w[Acme/app Acme/market_data Acme/produce], config.repository_names
    assert config.changelog_repository?("acme/app")
    assert_not config.changelog_repository?("ACME/market_data")
    assert config.changelog_repository?("Acme/produce")
    assert_equal({ name: "Acme/market_data", changelog: false, gem: "market_data" }, config.repository_options("acme/market_data"))
    assert_equal({ name: "Acme/app", changelog: true, gem: nil }, config.repository_options("Acme/app"))
    assert_nil config.repository_options("Acme/other")
    assert_equal({ "market_data" => "Acme/market_data", "acme-produce" => "Acme/produce" }, config.tracked_gems)
  end

  test "repository_configured? finds Hash entries case-insensitively" do
    config = Shiplog::Configuration.new
    config.repositories = [ { name: "Acme/Widgets", changelog: false } ]
    assert_equal "Acme/Widgets", config.repository_configured?("acme/widgets")
  end

  test "repositories validates Hash options" do
    config = Shiplog::Configuration.new
    assert_raises(ArgumentError) { config.repositories = [ { changelog: false } ] }
    assert_raises(ArgumentError) { config.repositories = [ { name: "a/b", changelog: "no" } ] }
    assert_raises(ArgumentError) { config.repositories = [ { name: "a/b", gem: :sym } ] }
    assert_raises(ArgumentError) { config.repositories = [ { name: "a/b", gem: "" } ] }
    assert_raises(ArgumentError) { config.repositories = [ { name: "a/b", bogus: 1 } ] }
    assert_raises(ArgumentError) { config.repositories = [ 42 ] }
    assert_raises(ArgumentError) { config.repositories = "a/b" }
  end

  test "lockfile_path defaults to Gemfile.lock" do
    assert_equal "Gemfile.lock", Shiplog::Configuration.new.lockfile_path
  end

  test "admin_chrome accepts :standalone and :hosted (as symbols or strings)" do
    config = Shiplog::Configuration.new
    config.admin_chrome = :hosted
    assert_equal :hosted, config.admin_chrome
    config.admin_chrome = "standalone"
    assert_equal :standalone, config.admin_chrome
  end

  test "admin_chrome rejects other values and lists the valid ones" do
    error = assert_raises(ArgumentError) { Shiplog::Configuration.new.admin_chrome = :fancy }
    assert_includes error.message, ":standalone"
    assert_includes error.message, ":hosted"
    assert_raises(ArgumentError) { Shiplog::Configuration.new.admin_chrome = nil }
  end

  test "classes= normalises string keys to symbols and stores a frozen copy" do
    config = Shiplog::Configuration.new
    input = { "card" => "rounded", entry: "p-4" }
    config.classes = input

    assert_equal({ card: "rounded", entry: "p-4" }, config.classes)
    assert config.classes.frozen?
    assert_not input.frozen?
    input[:page] = "x"
    assert_not config.classes.key?(:page)
  end

  test "classes= raises for unknown keys and lists the valid ones" do
    error = assert_raises(ArgumentError) { Shiplog::Configuration.new.classes = { cards: "grid", "bogus" => "x" } }
    assert_includes error.message, ":bogus"
    Shiplog::Classes::KEYS.each { |key| assert_includes error.message, key.to_s }
  end

  test "classes= accepts nil as empty" do
    config = Shiplog::Configuration.new
    config.classes = nil
    assert_equal({}, config.classes)
  end

  test "parent controller setters raise once the engine controllers are loaded" do
    Shiplog::PublicController
    Shiplog::Admin::ApplicationController

    error = assert_raises(ArgumentError) { Shiplog::Configuration.new.public_parent_controller = "ApplicationController" }
    assert_includes error.message, "config/initializers"
    assert_raises(ArgumentError) { Shiplog::Configuration.new.admin_parent_controller = "Admin::BaseController" }
  end

  def digest_config(**overrides)
    Shiplog::Configuration.new.tap do |config|
      config.classes = { card: "rounded", entry: %w[p-4 bg-white] }
      config.extra_pages = [ { label: "News", path: -> { "/news" } }, { label: -> { "Docs" }, path: "/docs" } ]
      config.repository_labels = { "Acme/ios" => "iPhone", "Acme/web" => -> { "Web" } }
      config.feedback_path = "/feedback"
      overrides.each { |key, value| config.public_send("#{key}=", value) }
    end
  end

  test "render_digest is equal for equal configurations built separately, lambdas included" do
    assert_equal digest_config.render_digest, digest_config.render_digest
    assert_match(/\A\h{64}\z/, digest_config.render_digest)
  end

  test "render_digest follows the values that change the markup" do
    base = digest_config.render_digest
    [ { classes: { card: "other" } }, { stylesheet: false }, { roadmap_shipped_count: 2 }, { feedback_path: "/other" },
      { repository_labels: { "Acme/ios" => "iOS" } }, { extra_pages: [ { label: "News", path: "/n" } ] },
      { cache_version: "2" } ].each do |change|
      assert_not_equal base, digest_config(**change).render_digest, "expected #{change.inspect} to change the digest"
    end
  end

  test "cache_version defaults to nil" do
    assert_nil Shiplog::Configuration.new.cache_version
  end

  test "the ETag digest never relies on the per-process Object#hash" do
    %w[lib/shiplog/configuration.rb app/controllers/shiplog/public_controller.rb app/controllers/shiplog/roadmaps_controller.rb].each do |file|
      assert_no_match(/\.hash\b/, File.read(Shiplog::Engine.root.join(file)), "#{file} uses #hash")
    end
  end

  test "extra_pages accepts relative, http(s) and mailto String paths only" do
    config = Shiplog::Configuration.new
    [ "/news", "https://example.com/news", "http://example.com", "mailto:hi@example.com" ].each do |path|
      config.extra_pages = [ { label: "X", path: } ]
    end
    [ "javascript:alert(1)", "data:text/html,x", "news", "//evil.example", "ftp://x" ].each do |path|
      assert_raises(ArgumentError, path) { config.extra_pages = [ { label: "X", path: } ] }
    end
  end
end
