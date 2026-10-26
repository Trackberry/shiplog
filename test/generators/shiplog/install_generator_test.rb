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

  test "the initializer explicitly opens the admin check and explains why" do
    run_generator_without_rake

    assert_file "config/initializers/shiplog.rb" do |content|
      assert_match(/^  config\.authorize_admin = ->\(controller\) \{ true \}/, content)
      assert_match(/route constraint around the admin mount does the authentication/, content)
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

  test "without --tailwind the styling settings stay commented out and Tailwind is untouched" do
    write_tailwind_css
    run_generator_without_rake

    assert_file "config/initializers/shiplog.rb" do |content|
      assert_match(/^  # config\.stylesheet = true$/, content)
      assert_match(/^  # config\.classes = \{\}$/, content)
      assert_no_match(/^\s*config\.stylesheet = false/, content)
      assert_no_match(/^\s*config\.classes = \{$/, content)
    end
    assert_equal "@import \"tailwindcss\";\n", File.read(File.join(destination_root, "app/assets/tailwind/application.css"))
  end

  test "--tailwind turns the bundled stylesheet off" do
    run_generator_without_rake(tailwind: true)

    assert_file "config/initializers/shiplog.rb" do |content|
      assert_match(/^  config\.stylesheet = false$/, content)
      assert_no_match(/^\s*# config\.stylesheet/, content)
    end
  end

  test "--tailwind writes Tailwind classes for every class key" do
    run_generator_without_rake(tailwind: true)

    assert system(RbConfig.ruby, "-c", File.join(destination_root, "config/initializers/shiplog.rb"), out: File::NULL)
    content = File.read(File.join(destination_root, "config/initializers/shiplog.rb"))
    classes = eval(content[/^  config\.classes = (\{.*?^  \})/m, 1])
    assert_equal Shiplog::Classes::KEYS.sort, classes.keys.sort
    assert classes.values.all?(&:present?)
    assert_equal "grid gap-6 md:grid-cols-3", classes[:columns]
    assert classes.values.any? { |value| value.include?("dark:") }
    assert classes.values.any? { |value| value.include?("indigo") }
  end

  test "--tailwind adds the @source line to the host's tailwind stylesheet" do
    write_tailwind_css
    run_generator_without_rake(tailwind: true)

    css = File.read(File.join(destination_root, "app/assets/tailwind/application.css"))
    assert_equal "@import \"tailwindcss\";\n@source \"../../../config/initializers/shiplog.rb\";\n", css
  end

  test "the @source path resolves to the initializer from the tailwind stylesheet" do
    write_tailwind_css
    run_generator_without_rake(tailwind: true)

    stylesheet_dir = Pathname.new(File.join(destination_root, "app/assets/tailwind"))
    relative = File.read(File.join(stylesheet_dir, "application.css"))[/@source "(.+)";/, 1]
    assert_equal File.join(destination_root, "config/initializers/shiplog.rb"), File.expand_path(relative, stylesheet_dir)
  end

  test "--tailwind does not add the @source line twice" do
    write_tailwind_css("@import \"tailwindcss\";\n@source \"../../../config/initializers/shiplog.rb\";\n")
    run_generator_without_rake(tailwind: true)

    css = File.read(File.join(destination_root, "app/assets/tailwind/application.css"))
    assert_equal 1, css.scan("@source").size
  end

  test "--tailwind prints the @source line when there is no tailwind stylesheet" do
    output = capture(:stdout) { run_generator_without_rake(tailwind: true) }

    assert_includes output, %(@source "../../../config/initializers/shiplog.rb";)
    assert_no_file "app/assets/tailwind/application.css"
  end

  private
    def write_tailwind_css(content = "@import \"tailwindcss\";\n")
      path = File.join(destination_root, "app/assets/tailwind/application.css")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    def run_generator_without_rake(options = {})
      commands = []
      generator = Shiplog::Generators::InstallGenerator.new([], options, destination_root:)
      generator.define_singleton_method(:rake) { |command, **| commands << command }
      generator.invoke_all
      commands
    end
end
