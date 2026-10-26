Shiplog::Admin::Engine.routes.draw do
  root to: "entries#index"
  resources :entries, only: %i[index edit update] do
    scope module: :entries do
      resource :approval, only: :create
      resource :discard, only: %i[create destroy]
      resource :rewrite, only: :create
    end
  end
  resource :board, only: %i[show update]
  resource :sync, only: %i[show create]
  get "assets/:version/:name", to: "/shiplog/frontends#show", as: :frontend, constraints: { version: /[^\/]+/, name: /[a-z_]+\.(css|js)/ }
end
