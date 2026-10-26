module Shiplog
  # Parent controller for the public pages. The parent class is resolved when this
  # file loads, so `config.public_parent_controller` must be set in an initializer
  # (config/initializers/shiplog.rb), not later at runtime.
  class PublicController < Shiplog.config.public_parent_controller.constantize
    helper Shiplog::FrontendHelper
    helper Shiplog::StylingHelper
    helper Shiplog::SwitcherHelper
    helper Shiplog::HostRoutesHelper
    layout -> { Shiplog.config.public_layout }

    private

    # What the rendered markup depends on besides the data: the locale, the gem version and the styling
    # config. Host parent controllers rendering per-user layout content should declare `etag { current_user&.id }`.
    def shiplog_etag_parts
      [ I18n.locale, Shiplog::VERSION, Shiplog.config.classes.hash, Shiplog.config.stylesheet ]
    end
  end
end
