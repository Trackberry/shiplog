module Shiplog
  # The newsletter's subscribe form. The changelog and announcement pages render it while config.newsletter is
  # on; a host renders it on any page with `helper Shiplog::NewsletterHelper` and `<%= shiplog_newsletter_form %>`
  # (or `render "shiplog/newsletter/form"` once the helper is included). Nothing is rendered while the newsletter
  # is off. Uses the engine's own route helpers, or the proxy of the host's mount in host views (see SwitcherHelper).
  module NewsletterHelper
    include Shiplog::SwitcherHelper

    # The form (and the bundled stylesheet once per host page, unless config.stylesheet is false). `source` is
    # recorded with the subscription as the page it was made on; the request's path by default.
    def shiplog_newsletter_form(source: nil)
      return "".html_safe unless Shiplog.newsletter?

      stylesheet = if Shiplog.config.stylesheet && !@_shiplog_stylesheet_emitted
        @_shiplog_stylesheet_emitted = true
        tag.link(rel: "stylesheet", nonce: content_security_policy_nonce,
          href: shiplog_routes.frontend_path(version: Shiplog::VERSION, name: "shiplog.css"))
      end
      safe_join([ stylesheet, render("shiplog/newsletter/form", source:) ])
    end

    # The form's action, in the engine's pages and the host's alike.
    def shiplog_newsletter_subscription_path = shiplog_routes.newsletter_subscription_path

    # The page the subscription is recorded as made on: the given source, else the request's path.
    def shiplog_newsletter_source(source) = (source.presence || request.path).to_s.first(NewsletterSubscriber::SOURCE_MAX_LENGTH)
  end
end
