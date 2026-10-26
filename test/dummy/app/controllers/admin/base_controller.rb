# Stands in for a host's admin base controller (authentication, chrome) that Shiplog's admin inherits from.
module Admin
  class BaseController < ApplicationController
    layout "host_admin"
    before_action { response.set_header("X-Host-Admin", "1") }
    # Like a host that switches locale from params[:locale]: any locale outside I18n.available_locales raises.
    around_action { |_controller, action| I18n.with_locale(params[:locale].presence || I18n.locale, &action) }
  end
end
