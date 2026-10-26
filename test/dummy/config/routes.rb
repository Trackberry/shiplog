Rails.application.routes.draw do
  # The host's own routes, which a host layout rendered inside an engine reaches through main_app.
  root "home#show"
  get "about", to: "home#about", as: :about
  get "account", to: "home#account", as: :account

  get "news", to: "pages#news", as: :news
  get "avatars/:id", to: "home#show", as: :host_avatar_image
  resolve("HostAvatar") { |avatar| route_for(:host_avatar_image, avatar.id) }

  mount Shiplog::Engine => "/"
  mount Shiplog::Admin::Engine => "/admin/shiplog"
end
