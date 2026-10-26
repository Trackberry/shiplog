module Shiplog
  # A host layout rendered by a Shiplog controller runs in the engine's isolated routing context, so
  # the host's own helpers (root_path, new_user_session_path, ...) are undefined there. This forwards
  # any unknown *_path / *_url call to main_app when the host app defines it. Helpers the engine
  # defines itself (roadmap_path, board_path, ...) are real methods and always win.
  module HostRoutesHelper
    def method_missing(name, ...)
      if shiplog_host_route?(name)
        main_app.public_send(name, ...)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      shiplog_host_route?(name) || super
    end

    private

    def shiplog_host_route?(name)
      name.end_with?("_path", "_url") && respond_to?(:main_app, true) && main_app.respond_to?(name)
    end
  end
end
