module Shiplog
  # The Roadmap / Changelog / extra pages switcher. The default page header renders it, and a host adds
  # `helper Shiplog::SwitcherHelper` to render it on its own pages (e.g. a news page): `<%= shiplog_switcher %>`.
  # It only uses the `shiplog` engine route proxy, so it works in main-app views too.
  module SwitcherHelper
    include Shiplog::StylingHelper
    include Shiplog::CallableHelper

    WARNED = Set.new
    private_constant :WARNED

    def self.reset_warnings! = WARNED.clear

    # The switcher for host pages: the bundled stylesheet (once per page, and not when the engine page already
    # linked it; unless config.stylesheet is false) and the nav.
    def shiplog_switcher
      stylesheet = if Shiplog.config.stylesheet && !@_shiplog_stylesheet_emitted
        @_shiplog_stylesheet_emitted = true
        tag.link(rel: "stylesheet", nonce: content_security_policy_nonce,
          href: shiplog.frontend_path(version: Shiplog::VERSION, name: "shiplog.css"))
      end
      safe_join([ stylesheet, render("shiplog/switcher") ])
    end

    # [{ label:, path:, current: }] in display order. A path with an unsafe scheme is nil (rendered as text).
    # Only the page with the longest matching path is current.
    def shiplog_switcher_pages
      pages = [
        { label: t("shiplog.switcher.roadmap"), path: shiplog.roadmap_path },
        { label: t("shiplog.switcher.changelog"), path: shiplog.changelog_path },
        *Shiplog.config.extra_pages.map { |page| { label: shiplog_resolve(page[:label]), path: shiplog_safe_url(shiplog_resolve(page[:path])) } }
      ]
      lengths = pages.map { |page| shiplog_match_length(page[:path]) }
      best = lengths.compact.max
      current = best && lengths.index(best)
      pages.each_with_index.map { |page, index| page.merge(current: index == current) }
    end

    # The URL when it is safe to link (see Configuration.safe_url?); otherwise nil, with a warning logged once.
    def shiplog_safe_url(url)
      return if url.blank?
      return url.to_s if Shiplog::Configuration.safe_url?(url)

      Rails.logger.warn("[Shiplog] Not linking #{url.inspect}: only paths, http(s) and mailto: URLs are allowed") if WARNED.add?(url.to_s)
      nil
    end

    private

    # Length of the link's path when it contains the request path (equal, or a parent segment), else nil.
    def shiplog_match_length(url)
      return if url.nil?

      prefix = (URI.parse(url).path || "").chomp("/")
      current = request.path.to_s.chomp("/")
      return (prefix.length if current == prefix) if prefix.empty?

      prefix.length if current == prefix || current.start_with?("#{prefix}/")
    rescue URI::InvalidURIError
      nil
    end
  end
end
