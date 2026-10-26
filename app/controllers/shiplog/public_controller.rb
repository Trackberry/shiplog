module Shiplog
  # Parent controller for the public pages. The parent class is resolved when this
  # file loads, so `config.public_parent_controller` must be set in an initializer
  # (config/initializers/shiplog.rb), not later at runtime.
  class PublicController < Shiplog.config.public_parent_controller.constantize
    helper Shiplog::FrontendHelper
    helper Shiplog::StylingHelper
    helper Shiplog::HostRoutesHelper
    layout -> { Shiplog.config.public_layout }
  end
end
