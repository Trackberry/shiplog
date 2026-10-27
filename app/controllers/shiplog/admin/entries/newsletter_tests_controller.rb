module Shiplog
  module Admin
    module Entries
      # "Send test": one copy of the newsletter to the current admin's address (config.current_admin, which gives
      # an email by default; nothing can be sent when it gives none), in the chosen locale. No delivery row: a
      # test never counts as a send, and it works before the announcement is approved or translated. The links in
      # it are real (the admin's own unsubscribe link), as in the final email.
      class NewsletterTestsController < ApplicationController
        def create
          entry = Entry.find(params[:entry_id])
          return head(:not_found) unless entry.announcement? && Shiplog.newsletter?

          email = current_admin_name.to_s.strip
          return back_with_alert(entry, t("shiplog.admin.newsletter.test_no_email")) unless URI::MailTo::EMAIL_REGEXP.match?(email)

          blockers = Newsletter.blockers(entry, test: true)
          return back_with_alert(entry, t("shiplog.admin.newsletter.send_blocked", reasons: blockers.map { |blocker| t("shiplog.admin.newsletter.blockers.#{blocker}", locales: "") }.join(", "))) if blockers.any?

          # test_locale, not locale: a host's around_action switching the locale from params[:locale] must not read it.
          locale = NewsletterSubscriber.resolve_locale(params[:test_locale])
          # Delivered now, in the request: a queued mail job would carry the admin's address (and unsubscribe link)
          # into the queue's storage. One message, so the wait is short, and a failure shows at once.
          NewsletterMailer.announcement(entry, email, locale:, unsubscribe_url: Newsletter.unsubscribe_url(email)).deliver_now
          redirect_to edit_entry_path(entry, inbox_filter_params), notice: t("shiplog.admin.newsletter.test_sent", email:, language: locale)
        rescue StandardError => error
          # The class only: a delivery error's message can carry the address or the mail server's details.
          Rails.logger.error("[shiplog] The newsletter test send failed: #{error.class}")
          back_with_alert(entry, t("shiplog.admin.newsletter.test_failed", error: error.class.name))
        end

        private

        def back_with_alert(entry, alert)
          redirect_to edit_entry_path(entry, inbox_filter_params), alert:
        end
      end
    end
  end
end
