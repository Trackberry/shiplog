module Shiplog
  class Engine < ::Rails::Engine
    isolate_namespace Shiplog

    # shiplog_head_tags in every view, so a layout shared with the host's own pages can call it.
    initializer "shiplog.head_tags_helper" do
      ActiveSupport.on_load(:action_view) { include Shiplog::HeadTagsHelper }
    end

    # Once per boot, after the host's initializers have set config.images: say why screenshots are off.
    config.after_initialize { Shiplog.log_images_status }
    # And why the newsletter, when on, cannot be sent yet.
    config.after_initialize { Shiplog.log_newsletter_status }
  end
end
