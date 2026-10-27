module Shiplog
  module Newsletter
    # The double opt-in link: a page with a button (GET changes nothing, link scanners prefetch), and the POST
    # that confirms. The token is signed and expires after 7 days (Newsletter::Tokens); an invalid one is a 404.
    # Rendered in the subscriber's language, whatever the page's URL.
    class ConfirmationsController < NewsletterController
      around_action :with_subscriber

      def show
      end

      def create
        @subscriber.confirm!
        render :create
      end

      private

      def with_subscriber
        @subscriber = Tokens.subscriber_for(params[:token])
        return render_invalid_link unless @subscriber

        I18n.with_locale(Newsletter.i18n_locale(@subscriber.locale)) { yield }
      end
    end
  end
end
