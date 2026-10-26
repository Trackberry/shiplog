module Shiplog
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Installs Shiplog: initializer, routes, migrations and the GitHub issue form."

      def copy_initializer
        template "initializer.rb.tt", "config/initializers/shiplog.rb"
      end

      def mount_engines
        route <<~RUBY
          # Shiplog: public roadmap, changelog and GitHub webhook.
          mount Shiplog::Engine => "/"

          # Shiplog admin. Wrap it in your own authentication before enabling it, for example with Devise:
          # authenticate :user, ->(user) { user.admin? } do
          #   mount Shiplog::Admin::Engine => "/admin/shiplog"
          # end
        RUBY
      end

      def install_migrations
        rake "shiplog:install:migrations"
      end

      def copy_issue_form
        copy_file "shiplog-feature.yml", ".github/ISSUE_TEMPLATE/shiplog-feature.yml"
      end
    end
  end
end
