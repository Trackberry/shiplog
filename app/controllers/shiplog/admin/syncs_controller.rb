module Shiplog
  module Admin
    class SyncsController < ApplicationController
      DELIVERIES_SHOWN = 20

      def show
        repositories = Repository.where(full_name: Shiplog.config.repositories).index_by(&:full_name)
        @repositories = Shiplog.config.repositories.map { |full_name| [ full_name, repositories[full_name] ] }
        @deliveries = WebhookDelivery.order(received_at: :desc, id: :desc).limit(DELIVERIES_SHOWN)
        @webhook_secret_missing = Shiplog.config.webhook_secret.blank?
        @github_token_missing = Shiplog.config.resolved_github_token.blank?
      end

      def create
        SyncJob.perform_later
        ScanChangesJob.perform_later if params[:scan] == "1"
        redirect_to sync_path, notice: t("shiplog.admin.sync.queued")
      end
    end
  end
end
