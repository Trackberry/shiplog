require "test_helper"

class Shiplog::ConfigurationTest < ActiveSupport::TestCase
  test "defaults" do
    config = Shiplog.config
    assert_equal "public", config.public_label
    assert_equal %w[soon], config.soon_labels
    assert_equal %w[feat fix perf], config.commit_types
    assert_equal "roadmap", config.roadmap_path
    assert_equal "changelog", config.changelog_path
    assert_equal "ActionController::Base", config.public_parent_controller
    assert config.authorize_admin.call(Object.new)
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
end
