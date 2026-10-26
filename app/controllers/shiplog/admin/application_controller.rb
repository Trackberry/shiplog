module Shiplog
  module Admin
    class ApplicationController < ActionController::Base
      protect_from_forgery with: :exception

      helper Shiplog::FrontendHelper
      helper Shiplog::ApplicationHelper
      helper Shiplog::Admin::EntriesHelper
      helper_method :current_admin_name
      layout "shiplog/admin"

      before_action :authorize_admin

      rescue_from Shiplog::Entry::InvalidTransition do
        redirect_to edit_entry_path(params[:entry_id]), alert: t("shiplog.admin.entries.invalid_transition")
      end

      private

      def authorize_admin
        head :forbidden unless Shiplog.config.authorize_admin.call(self)
      end

      def current_admin_name
        Shiplog.config.current_admin.call(self)
      end
    end
  end
end
