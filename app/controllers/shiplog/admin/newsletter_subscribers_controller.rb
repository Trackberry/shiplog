module Shiplog
  module Admin
    # The newsletter's subscribers (the visitors who subscribed through Shiplog's form; the host's users are its
    # own): counts per locale and status, a searchable paginated list, removal, and a CSV export (.csv, the
    # search applied; cells that look like formulas are neutralised, see Newsletter::Csv).
    class NewsletterSubscribersController < ApplicationController
      PER_PAGE = 100
      MAX_PAGE = 100_000

      before_action :require_newsletter

      def index
        @query = params[:q].is_a?(String) ? params[:q].squish.first(NewsletterSubscriber::EMAIL_MAX_LENGTH) : ""
        scope = NewsletterSubscriber.search(@query).newest_first
        respond_to do |format|
          format.html do
            @counts = NewsletterSubscriber.counts_by_locale
            @page = page_number
            records = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
            @more = records.size > PER_PAGE
            @subscribers = records.first(PER_PAGE)
          end
          format.csv do
            send_data Newsletter::Csv.generate(scope), type: "text/csv; charset=utf-8", disposition: "attachment",
              filename: "shiplog-newsletter-subscribers-#{Date.current.iso8601}.csv"
          end
        end
      end

      def destroy
        subscriber = NewsletterSubscriber.find(params[:id])
        subscriber.destroy!
        redirect_to newsletter_subscribers_path(q: params[:q].presence), notice: t("shiplog.admin.newsletter.removed", email: subscriber.email)
      end

      private

      def require_newsletter
        head :not_found unless Shiplog.newsletter?
      end

      def page_number
        Integer(params[:page].to_s, 10, exception: false).to_i.clamp(1, MAX_PAGE)
      end
    end
  end
end
