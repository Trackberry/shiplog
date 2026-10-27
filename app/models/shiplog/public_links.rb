module Shiplog
  # Links to the public pages built outside a request (drafting, exports, the approval hook): config.canonical_url
  # plus the path where the host mounted Shiplog::Engine, or the path alone when canonical_url is not set. Views
  # use PermalinkHelper instead, which knows the request.
  module PublicLinks
    # The URL of an entry's permalink page (features, changes and announcements), or nil when it has no valid slug.
    def self.entry_url(entry) = (url(:changelog_entry_path, entry.slug) if entry.permalink?)

    def self.changelog_url = url(:changelog_path)

    def self.url(helper, *args) = "#{Shiplog.config.canonical_url}#{path(helper, *args)}"

    # The path of a named engine route, with the engine's mount in front. A blank script_name makes Rails look
    # the mount up again (and fail under a required segment), so a root mount passes "/", which Rails strips.
    def self.path(helper, *args)
      Engine.routes.url_helpers.public_send(helper, *args, script_name: mount_path.presence || "/")
    end

    # The path Shiplog::Engine is mounted at in the host's routes: "" for "/", "/updates" for a mount below it. An
    # optional segment of a scope around the mount (`scope "(:locale)"`) is left out, which gives the default
    # locale's URL. A required one (`scope ":tenant"`) cannot be filled outside a request: the root is used, and
    # a warning logged.
    def self.mount_path
      route = Rails.application.routes.routes.find { |candidate| engine_route?(candidate) }
      return "" unless route

      if route.required_parts.any?
        Rails.logger&.warn("[shiplog] Shiplog::Engine is mounted under required segments (#{route.path.spec}): links built outside a request use \"/\"")
        return ""
      end
      route.format({}).delete_suffix("/")
    end

    # Whether a host route mounts the engine, directly or through a constraints wrapper.
    def self.engine_route?(route)
      app = route.app
      3.times do
        return true if app == Engine
        return false if app.is_a?(Class) || !app.respond_to?(:app)

        app = app.app
      end
      false
    end
    private_class_method :engine_route?
  end
end
