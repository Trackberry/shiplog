module Shiplog
  # The Roadmap / Changelog / extra pages switcher. The default page header renders it, and a host adds
  # `helper Shiplog::SwitcherHelper` to render it on its own pages (e.g. a news page): `<%= shiplog_switcher %>`.
  # It only uses the `shiplog` engine route proxy, so it works in main-app views too.
  module SwitcherHelper
    include Shiplog::StylingHelper
    include Shiplog::CallableHelper

    # The switcher for host pages: the bundled stylesheet (unless config.stylesheet is false) and the nav.
    def shiplog_switcher
      stylesheet = if Shiplog.config.stylesheet
        tag.link(rel: "stylesheet", nonce: content_security_policy_nonce,
          href: shiplog.frontend_path(version: Shiplog::VERSION, name: "shiplog.css"))
      end
      safe_join([ stylesheet, render("shiplog/switcher") ])
    end

    # [{ label:, path:, current: }] in display order.
    def shiplog_switcher_pages
      pages = [
        { label: t("shiplog.switcher.roadmap"), path: shiplog.roadmap_path },
        { label: t("shiplog.switcher.changelog"), path: shiplog.changelog_path },
        *Shiplog.config.extra_pages.map { |page| { label: shiplog_resolve(page[:label]), path: shiplog_resolve(page[:path]) } }
      ]
      pages.map { |page| page.merge(current: shiplog_current_page?(page[:path])) }
    end

    private

    def shiplog_current_page?(path)
      prefix = path.to_s.chomp("/")
      current = request.path.to_s.chomp("/")
      return current == prefix if prefix.empty?
      current == prefix || current.start_with?("#{prefix}/")
    end
  end
end
