module Shiplog
  class Engine < ::Rails::Engine
    isolate_namespace Shiplog

    # Once per boot, after the host's initializers have set config.images: say why screenshots are off.
    config.after_initialize { Shiplog.log_images_status }
  end
end
