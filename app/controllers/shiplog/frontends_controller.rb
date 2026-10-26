module Shiplog
  class FrontendsController < ApplicationController
    ASSET_DIRECTORY = Engine.root.join("app/frontend/shiplog")
    ASSETS = {
      "shiplog.css" => { path: ASSET_DIRECTORY.join("shiplog.css"), type: "text/css" },
      "admin.css" => { path: ASSET_DIRECTORY.join("admin.css"), type: "text/css" },
      "board.js" => { path: ASSET_DIRECTORY.join("board.js"), type: "text/javascript" },
      "inbox.js" => { path: ASSET_DIRECTORY.join("inbox.js"), type: "text/javascript" }
    }.freeze

    # The version segment busts caches; stale versions are 404 so they are never cached as the current file.
    skip_after_action :verify_same_origin_request, raise: false

    def show
      return head(:not_found) unless params[:version] == Shiplog::VERSION

      asset = ASSETS[params[:name].to_s] or return head(:not_found)
      expires_in 1.year, public: true, immutable: true
      send_file asset[:path], type: asset[:type], disposition: :inline
    end
  end
end
