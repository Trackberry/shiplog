module Shiplog
  module Newsletter
    # A subscriber's preferences, reached through the token of the newsletter's footer, without an account:
    # change the language, unsubscribe, resubscribe (the token proves the mailbox, so no new confirmation), and
    # "delete my data", which removes the row. The token is rotated after each change (the next page uses the
    # new one; the link in the old email stops working). Rendered in the subscriber's language, and still
    # available while config.newsletter is off, so an old email's link keeps working.
    class PreferencesController < NewsletterController
      skip_before_action :require_newsletter
      before_action :require_newsletter_tables
      around_action :with_subscriber

      def show
      end

      # locale (one of the allowed ones) and/or subscribed ("0" unsubscribes from both lists, "1" resubscribes).
      # The notice is worded in the language just chosen, which the next page is in.
      def update
        notice = "saved"
        case params[:subscribed]
        when "0"
          Newsletter.unsubscribe(@subscriber.email)
          notice = "unsubscribed"
        when "1"
          @subscriber.resubscribe!
          notice = "resubscribed"
        end
        @subscriber.update!(locale: NewsletterSubscriber.resolve_locale(params[:locale])) if params[:locale].is_a?(String)
        @subscriber.rotate_token!
        I18n.with_locale(Newsletter.i18n_locale(@subscriber.locale)) do
          redirect_to newsletter_preferences_path(@subscriber.token), notice: t("shiplog.newsletter.preferences.#{notice}")
        end
      end

      def destroy
        @subscriber.destroy!
        render :destroy
      end

      private

      def with_subscriber
        @subscriber = NewsletterSubscriber.find_by(token: params[:token].to_s)
        return render_invalid_link unless @subscriber

        I18n.with_locale(Newsletter.i18n_locale(@subscriber.locale)) { yield }
      end
    end
  end
end
