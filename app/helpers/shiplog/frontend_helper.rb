module Shiplog
  module FrontendHelper
    def shiplog_stylesheet_tag(name)
      @_shiplog_stylesheet_emitted = true if name == "shiplog" # shiplog_switcher then skips its own link
      tag.link rel: "stylesheet", href: shiplog_asset_path("#{name}.css"), nonce: content_security_policy_nonce
    end

    def shiplog_javascript_tag(name)
      tag.script "", src: shiplog_asset_path("#{name}.js"), type: "module", nonce: content_security_policy_nonce
    end

    private

    def shiplog_asset_path(file)
      frontend_path(version: Shiplog::VERSION, name: file)
    end
  end
end
