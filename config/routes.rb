Shiplog::Engine.routes.draw do
  get Shiplog.config.roadmap_path, to: "roadmaps#show", as: :roadmap
  # The feed and the permalinks come before the plain changelog route, whose optional (.:format) would
  # otherwise take /changelog.atom. A slug has no dot, and the permalink takes no format.
  get "#{Shiplog.config.changelog_path}.atom", to: "changelog_feeds#show", as: :changelog_feed, defaults: { format: "atom" }
  get "#{Shiplog.config.changelog_path}/:slug", to: "changelog_entries#show", as: :changelog_entry,
    format: false, constraints: { slug: /[a-z0-9-]+/ }
  get Shiplog.config.changelog_path, to: "changelogs#show", as: :changelog
  post "shiplog/github/webhook", to: "webhooks#create", as: :github_webhook
  # The newsletter's pages live under shiplog/ (like the webhook), so a host that constrains the engine's mount to
  # the changelog, the roadmap and /shiplog/ lets them through. Links from emails open a page with a button
  # (GET), and the button POSTs: nothing changes state on a GET. A token is URL-safe base64 or base58.
  token = { token: /[A-Za-z0-9_-]+/ }
  get "shiplog/newsletter/subscription", to: "newsletter/subscriptions#show", as: :newsletter_subscription
  post "shiplog/newsletter/subscription", to: "newsletter/subscriptions#create"
  get "shiplog/newsletter/confirm/:token", to: "newsletter/confirmations#show", as: :newsletter_confirmation, constraints: token, format: false
  post "shiplog/newsletter/confirm/:token", to: "newsletter/confirmations#create", constraints: token, format: false
  get "shiplog/newsletter/preferences/:token", to: "newsletter/preferences#show", as: :newsletter_preferences, constraints: token, format: false
  patch "shiplog/newsletter/preferences/:token", to: "newsletter/preferences#update", constraints: token, format: false
  delete "shiplog/newsletter/preferences/:token", to: "newsletter/preferences#destroy", constraints: token, format: false
  get "shiplog/newsletter/unsubscribe/:token", to: "newsletter/unsubscriptions#show", as: :newsletter_unsubscription, constraints: token, format: false
  post "shiplog/newsletter/unsubscribe/:token", to: "newsletter/unsubscriptions#create", constraints: token, format: false
  get "shiplog/assets/:version/:name", to: "frontends#show", as: :frontend, constraints: { version: /[^\/]+/, name: /[a-z_]+\.(css|js)/ }
end
