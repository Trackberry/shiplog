# Stands in for a host's admin base controller (authentication, chrome) that Shiplog's admin inherits from.
module Admin
  class BaseController < ApplicationController
    layout "host_admin"
    before_action { response.set_header("X-Host-Admin", "1") }
  end
end
