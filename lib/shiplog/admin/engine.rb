module Shiplog
  module Admin
    class Engine < ::Rails::Engine
      isolate_namespace Shiplog::Admin
      engine_name "shiplog_admin"
      config.paths["config/routes.rb"] = "config/admin_routes.rb"
    end
  end
end
