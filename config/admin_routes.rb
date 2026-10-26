Shiplog::Admin::Engine.routes.draw do
  root to: "entries#index"
  resource :board, only: :show
  resource :sync, only: :show
  get "assets/:version/:name", to: "/shiplog/frontends#show", as: :frontend, constraints: { version: /[^\/]+/, name: /[a-z_]+\.(css|js)/ }
end
