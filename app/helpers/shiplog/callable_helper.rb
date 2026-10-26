module Shiplog
  module CallableHelper
    # A config value that is a String, or a callable evaluated in the view so it can use route helpers
    # and I18n (`-> { main_app.news_path }`, `-> { t("...") }`).
    def shiplog_resolve(value)
      case value
      when Proc then instance_exec(&value)
      else value.respond_to?(:call) ? value.call : value
      end
    end
  end
end
