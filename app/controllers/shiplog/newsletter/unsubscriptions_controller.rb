module Shiplog
  module Newsletter
    # The unsubscribe link of every newsletter, for the host's users and Shiplog's subscribers alike: the token is
    # the encrypted email (Newsletter::Tokens), so Shiplog needs no row for a host user until they unsubscribe.
    # GET shows a page with a button; POST unsubscribes the address from both lists (Newsletter.unsubscribe,
    # which keeps a suppression row and calls config.on_newsletter_unsubscribe). The POST is also the RFC 8058
    # one-click target the List-Unsubscribe-Post header names: the mail provider sends it with the body
    # "List-Unsubscribe=One-Click" and no CSRF token, so the action checks none; the token in the URL is what
    # authorises it. Still available while config.newsletter is off: an old email's link must keep working.
    class UnsubscriptionsController < NewsletterController
      skip_before_action :require_newsletter
      before_action :require_newsletter_tables
      skip_forgery_protection only: :create

      around_action :with_email

      def show
      end

      def create
        Newsletter.unsubscribe(@email)
        render :create
      end

      private

      def with_email
        @email = Tokens.email_for(params[:token])
        return render_invalid_link unless @email

        subscriber = NewsletterSubscriber.find_by_email(@email)
        I18n.with_locale(Newsletter.i18n_locale(subscriber ? subscriber.locale : I18n.locale)) { yield }
      end
    end
  end
end
