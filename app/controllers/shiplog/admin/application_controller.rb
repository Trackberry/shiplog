module Shiplog
  module Admin
    # Parent controller of the admin. The parent class is resolved when this file loads, so
    # `config.admin_parent_controller` must be set in an initializer (config/initializers/shiplog.rb).
    class ApplicationController < Shiplog.config.admin_parent_controller.constantize
      include InboxFilters

      protect_from_forgery with: :exception

      helper Shiplog::FrontendHelper
      helper Shiplog::HostRoutesHelper
      helper Shiplog::ApplicationHelper
      helper Shiplog::Admin::EntriesHelper
      helper_method :current_admin_name, :shiplog_admin_hosted?
      layout -> { Shiplog.config.admin_layout }

      before_action :authorize_admin

      rescue_from Shiplog::Entry::InvalidTransition do
        respond_inline_error(t("shiplog.admin.entries.invalid_transition"), edit_entry_path(params[:entry_id], inbox_filter_params))
      end

      private

      def authorize_admin
        head :forbidden unless Shiplog.config.authorize_admin.call(self)
      end

      # True when the admin renders inside a host layout (config.admin_chrome = :hosted).
      def shiplog_admin_hosted?
        Shiplog.config.admin_chrome == :hosted
      end

      def current_admin_name
        Shiplog.config.current_admin.call(self)
      end
    end
  end
end
