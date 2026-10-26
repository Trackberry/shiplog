Rails.application.routes.draw do
  # The host's own routes, which a host layout rendered inside an engine reaches through main_app.
  root "home#show"
  get "about", to: "home#about", as: :about
  get "account", to: "home#account", as: :account

  mount Shiplog::Engine => "/"
  mount Shiplog::Admin::Engine => "/admin/shiplog"
end
