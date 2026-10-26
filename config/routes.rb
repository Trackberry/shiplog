Shiplog::Engine.routes.draw do
  get Shiplog.config.roadmap_path, to: "roadmaps#show", as: :roadmap
  # The feed and the permalinks come before the plain changelog route, whose optional (.:format) would
  # otherwise take /changelog.atom. A slug has no dot, and the permalink takes no format.
  get "#{Shiplog.config.changelog_path}.atom", to: "changelog_feeds#show", as: :changelog_feed, defaults: { format: "atom" }
  get "#{Shiplog.config.changelog_path}/:slug", to: "changelog_entries#show", as: :changelog_entry,
    format: false, constraints: { slug: /[a-z0-9-]+/ }
  get Shiplog.config.changelog_path, to: "changelogs#show", as: :changelog
  post "shiplog/github/webhook", to: "webhooks#create", as: :github_webhook
  get "shiplog/assets/:version/:name", to: "frontends#show", as: :frontend, constraints: { version: /[^\/]+/, name: /[a-z_]+\.(css|js)/ }
end
