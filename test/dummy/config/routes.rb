Rails.application.routes.draw do
  # The host's own routes, which a host layout rendered inside an engine reaches through main_app.
  root "home#show"
  get "about", to: "home#about", as: :about
  get "account", to: "home#account", as: :account

  get "news", to: "pages#news", as: :news
  get "news/archive", to: "pages#news"
  get "avatars/:id", to: "home#show", as: :host_avatar_image
  resolve("HostAvatar") { |avatar| route_for(:host_avatar_image, avatar.id) }

  mount Shiplog::Engine => "/"
  mount Shiplog::Admin::Engine => "/admin/shiplog"

  # A host route below the changelog path, declared after the mount: the engine's permalink route would shadow it
  # without the cascade for unknown slugs.
  get "changelog/archive", to: "pages#news", as: :changelog_archive
end
