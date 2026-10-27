module Shiplog
  module Newsletter
    # The subscribe form's target and the "check your inbox" page it leads to.
    class SubscriptionsController < NewsletterController
      PER_IP = 20
      PER_EMAIL = 3
      # All confirmation emails together, an hour: a ceiling on what a distributed bot can make Shiplog send.
      GLOBAL = 300
      WINDOW = 1.hour
      # The honeypot's field name: nothing a browser autofills (no "website", "url", "phone"...).
      HONEYPOT = :nl_extra

      # The form sits on public pages that are served with ETags: a 304 revisits a cached page, whose CSRF token
      # may belong to another session or be expired, and a host layout may cache it further. So the form sends no
      # token and this action checks none: it changes no session state, and nothing happens until the address
      # confirms by email (double opt-in), so a forged POST can at most send someone a confirmation email, which
      # the rate limits bound.
      skip_forgery_protection only: :create

      # Rails.cache counts the attempts (a null store counts nothing: the limits are then off, as in tests). The
      # per-address count is keyed by a digest of the normalised address (Newsletter.rate_limit_key), so the cache
      # holds no address and "a+tag@gmail.com" and "a.b@gmail.com" count as one.
      rate_limit to: PER_IP, within: WINDOW, by: -> { request.remote_ip }, with: -> { rate_limited }, name: "ip", only: :create
      rate_limit to: PER_EMAIL, within: WINDOW, by: -> { submitted_email.present? ? Newsletter.rate_limit_key(submitted_email) : request.remote_ip }, with: -> { rate_limited }, name: "email", only: :create
      rate_limit to: GLOBAL, within: WINDOW, by: -> { "all" }, with: -> { rate_limited }, name: "global", only: :create

      # The same redirect for a new, pending, confirmed or unsubscribed address (and for a bot that filled the
      # honeypot): the form cannot tell who is subscribed. Only an address that is not an email gets the form back.
      def create
        return redirect_to(newsletter_subscription_path) if params[HONEYPOT].present?

        subscriber = NewsletterSubscriber.subscribe(submitted_email, locale: I18n.locale, source: submitted_source)
        if subscriber
          redirect_to newsletter_subscription_path
        else
          @error = t("shiplog.newsletter.form.invalid_email", default: "Enter a valid email address.")
          @email = submitted_email
          render :show, status: :unprocessable_content
        end
      end

      # "Check your inbox to confirm."
      def show
      end

      private

      def submitted_email
        value = params[:email]
        value.is_a?(String) ? value.strip.downcase.first(NewsletterSubscriber::EMAIL_MAX_LENGTH + 1) : ""
      end

      # The page the visitor subscribed on: the form's `source` when it is a same-site path, else the referrer's
      # path (NewsletterSubscriber.clean_source has the last word).
      def submitted_source
        value = params[:source]
        return value if value.is_a?(String) && NewsletterSubscriber.clean_source(value)

        referer = request.referer.to_s
        URI.parse(referer).path if referer.present?
      rescue URI::InvalidURIError
        nil
      end

      def rate_limited
        render "shiplog/newsletter/rate_limited", status: :too_many_requests
      end
    end
  end
end
