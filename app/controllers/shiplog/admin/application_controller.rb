module Shiplog
  module Admin
    class ApplicationController < ActionController::Base
      helper Shiplog::FrontendHelper
      layout "shiplog/admin"
    end
  end
end
