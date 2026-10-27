module Shiplog
  # Parent of the newsletter's public pages (subscribe, confirm, preferences, unsubscribe), all under /shiplog/
  # so a host that constrains the engine's mount to its own paths lets them through. Subscribing and confirming
  # answer 404 while the newsletter is off; the unsubscribe and preferences pages keep working as long as the
  # tables exist (a link in an old email must still unsubscribe). None is ever cached: they are personal (a
  # token in the URL) or carry a fresh CSRF token.
  #
  # None of them changes state on a GET: email link scanners prefetch links, so a link in an email opens a page
  # with a button, and the button POSTs. The one-click unsubscribe (RFC 8058) is the exception by design: the
  # mail provider POSTs it (see Newsletter::UnsubscriptionsController).
  class NewsletterController < PublicController
    helper Shiplog::NewsletterHelper

    before_action :require_newsletter
    before_action :no_store

    private

    def require_newsletter
      head :not_found unless Shiplog.newsletter?
    end

    # For the pages that outlive config.newsletter: the tables must be there.
    def require_newsletter_tables
      head :not_found unless Newsletter.available?
    end

    # The page for a link that does not verify (tampered, expired, used, or a deleted subscriber). A 404 carries
    # no hint of which.
    def render_invalid_link
      render "shiplog/newsletter/invalid", status: :not_found
    end
  end
end
