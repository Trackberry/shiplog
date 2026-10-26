module Shiplog
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Installs Shiplog: initializer, routes, migrations and the GitHub issue form."

      class_option :tailwind, type: :boolean, default: false,
        desc: "Style the public pages with Tailwind: turn the bundled stylesheet off and generate config.classes"

      TAILWIND_STYLESHEET = "app/assets/tailwind/application.css".freeze
      # Relative to app/assets/tailwind/application.css: ../ is app/assets, ../../ is app, ../../../ is the app root.
      TAILWIND_SOURCE = %(@source "../../../config/initializers/shiplog.rb";).freeze

      # Neutral Tailwind v4 classes (gray scale, indigo accent, dark: variants) for every Shiplog::Classes key.
      TAILWIND_CLASSES = {
        page: "mx-auto max-w-6xl px-4 py-8 text-gray-900 dark:text-gray-100",
        page_header: "mb-8",
        page_title: "text-3xl font-semibold tracking-tight",
        page_lede: "mt-2 text-gray-600 dark:text-gray-400",
        switcher: "mt-6 inline-flex gap-1 rounded-full bg-gray-100 p-1 text-sm font-medium dark:bg-gray-900",
        switcher_link: "rounded-full px-4 py-1.5 text-gray-600 transition-colors hover:text-gray-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 aria-[current=page]:bg-white aria-[current=page]:text-gray-900 aria-[current=page]:shadow-sm dark:text-gray-400 dark:hover:text-white dark:aria-[current=page]:bg-gray-700 dark:aria-[current=page]:text-white",
        columns: "grid gap-6 md:grid-cols-3",
        column: "rounded-xl border border-gray-200 bg-gray-50 p-4 dark:border-gray-800 dark:bg-gray-900/50",
        column_header: "mb-4 border-b border-gray-200 pb-3 dark:border-gray-800",
        column_marker: "mr-2 inline-block h-2 w-2 rounded-full bg-gray-400 in-[.shiplog-column--in-progress]:bg-indigo-600 in-[.shiplog-column--coming-soon]:bg-indigo-300",
        column_title: "inline text-base font-semibold",
        column_count: "ml-2 rounded-full bg-gray-200 px-2 py-0.5 text-xs font-medium text-gray-700 dark:bg-gray-800 dark:text-gray-300",
        column_description: "mt-1 text-sm text-gray-500 dark:text-gray-400",
        column_empty: "text-sm text-gray-500 dark:text-gray-400",
        cards: "space-y-3",
        card: "rounded-lg border border-gray-200 bg-white p-3 shadow-sm transition hover:border-indigo-400 hover:shadow dark:border-gray-800 dark:bg-gray-900 dark:hover:border-indigo-500",
        card_title: "font-medium",
        card_body: "mt-1 text-sm text-gray-600 dark:text-gray-400",
        card_meta: "mt-3 flex flex-wrap items-center gap-2 text-xs font-medium text-gray-500 dark:text-gray-400",
        card_tag: "rounded-md bg-gray-100 px-2 py-0.5 text-gray-700 dark:bg-white/10 dark:text-gray-300",
        shipped: "mt-12 grid grid-cols-[1fr_auto] items-baseline gap-x-6 gap-y-4 border-t border-gray-200 pt-8 dark:border-gray-800",
        shipped_title: "text-lg font-semibold",
        shipped_list: "col-span-2 grid gap-6 sm:grid-cols-2 lg:grid-cols-4",
        shipped_item: "flex flex-col gap-1",
        shipped_date: "text-xs tabular-nums text-gray-500 dark:text-gray-400",
        shipped_link: "text-sm font-semibold text-gray-900 hover:text-indigo-600 dark:text-white dark:hover:text-indigo-400",
        footnote: "mt-10 border-t border-gray-200 pt-6 text-center text-sm text-gray-500 dark:border-gray-800 dark:text-gray-400",
        footnote_link: "font-medium text-indigo-600 hover:underline dark:text-indigo-400",
        months: "space-y-10",
        month: "border-l-2 border-gray-200 pl-6 dark:border-gray-800",
        month_title: "mb-4 text-lg font-semibold",
        entries: "space-y-4",
        entry: "rounded-lg border border-gray-200 bg-white p-4 dark:border-gray-800 dark:bg-gray-900",
        entry_feature: "border-l-4 border-l-indigo-500",
        entry_category: "mr-2 inline-block rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700 dark:bg-gray-800 dark:text-gray-300",
        entry_title: "mt-2 text-base font-semibold",
        entry_body: "mt-1 text-sm text-gray-600 dark:text-gray-400",
        entry_date: "text-xs text-gray-500 dark:text-gray-400",
        pagination: "mt-8 flex justify-between",
        pagination_link: "text-sm font-medium text-indigo-600 hover:underline dark:text-indigo-400",
        empty: "text-gray-500 dark:text-gray-400",
        search: "my-4 flex gap-2",
        search_input: "min-w-0 flex-1 rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm dark:border-gray-700 dark:bg-gray-900",
        search_button: "rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-500",
        search_summary: "mb-4 text-sm text-gray-500 dark:text-gray-400",
        search_clear: "ml-2 font-medium text-indigo-600 hover:underline dark:text-indigo-400",
        search_empty: "text-gray-500 dark:text-gray-400",
        permalink: "mx-auto max-w-2xl rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-800 dark:bg-gray-900",
        permalink_back: "mt-6 inline-block text-sm font-medium text-indigo-600 hover:underline dark:text-indigo-400",
        permalink_nav: "mt-8 flex flex-wrap justify-between gap-4 border-t border-gray-200 pt-4 dark:border-gray-800",
        permalink_nav_link: "text-sm font-medium text-indigo-600 hover:underline dark:text-indigo-400"
      }.freeze

      def copy_initializer
        template "initializer.rb.tt", "config/initializers/shiplog.rb"
      end

      def add_tailwind_source
        return unless options[:tailwind]

        path = File.join(destination_root, TAILWIND_STYLESHEET)
        if File.exist?(path)
          css = File.read(path)
          if css.include?(TAILWIND_SOURCE)
            say_status :identical, TAILWIND_STYLESHEET
          else
            separator = css.empty? || css.end_with?("\n") ? "" : "\n"
            append_to_file TAILWIND_STYLESHEET, "#{separator}#{TAILWIND_SOURCE}\n"
          end
        else
          say "Add this line to your Tailwind stylesheet so Tailwind compiles the Shiplog classes:\n  #{TAILWIND_SOURCE}"
        end
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

      private

      def tailwind_classes_ruby
        TAILWIND_CLASSES.map { |key, value| %(    #{key}: "#{value}",\n) }.join.sub(/,\n\z/, "\n")
      end
    end
  end
end
