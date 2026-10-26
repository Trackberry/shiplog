Shiplog::Engine.routes.draw do
  get Shiplog.config.roadmap_path, to: "roadmaps#show", as: :roadmap
  get Shiplog.config.changelog_path, to: "changelogs#show", as: :changelog
  post "shiplog/github/webhook", to: "webhooks#create", as: :github_webhook
  get "shiplog/assets/:version/:name", to: "frontends#show", as: :frontend, constraints: { version: /[^\/]+/, name: /[a-z_]+\.(css|js)/ }
end
