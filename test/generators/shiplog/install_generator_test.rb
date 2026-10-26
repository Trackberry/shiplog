require "test_helper"
require "rails/generators/test_case"
require "generators/shiplog/install/install_generator"

class Shiplog::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  tests Shiplog::Generators::InstallGenerator
  destination File.expand_path("../../../tmp/generators", __dir__)

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  test "creates an initializer documenting every configuration key" do
    run_generator_without_rake

    assert_file "config/initializers/shiplog.rb" do |content|
      keys = Shiplog::Configuration.instance_methods(false).grep(/=\z/).map { |name| name.to_s.chomp("=") }
      keys.each { |key| assert_includes content, "config.#{key} =", "missing #{key}" }
      assert_includes content, "acme/app"
    end
  end

  test "the generated initializer is valid Ruby" do
    run_generator_without_rake

    assert system(RbConfig.ruby, "-c", File.join(destination_root, "config/initializers/shiplog.rb"), out: File::NULL)
  end

  test "mounts the public engine and shows the admin mount as a commented example" do
    run_generator_without_rake

    assert_file "config/routes.rb" do |content|
      assert_match(/^  mount Shiplog::Engine => "\/"$/, content)
      assert_match(/^  # authenticate :user, ->\(user\) \{ user.admin\? \} do$/, content)
      assert_match(/^  #   mount Shiplog::Admin::Engine => "\/admin\/shiplog"$/, content)
      assert_no_match(/^\s*mount Shiplog::Admin/, content)
    end
  end

  test "installs migrations through the engine rake task" do
    assert_equal [ "shiplog:install:migrations" ], run_generator_without_rake
  end

  test "copies the issue form" do
    run_generator_without_rake

    assert_file ".github/ISSUE_TEMPLATE/shiplog-feature.yml" do |content|
      assert_equal File.read(Shiplog::Generators::InstallGenerator.source_root + "/shiplog-feature.yml"), content
    end
  end

  private
    def run_generator_without_rake
      commands = []
      generator = Shiplog::Generators::InstallGenerator.new([], {}, destination_root:)
      generator.define_singleton_method(:rake) { |command, **| commands << command }
      generator.invoke_all
      commands
    end
end
