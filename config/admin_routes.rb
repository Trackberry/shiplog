Shiplog::Admin::Engine.routes.draw do
  root to: "entries#index"
  resources :entries, only: %i[index edit update] do
    scope module: :entries do
      resource :approval, only: :create
      resource :discard, only: %i[create destroy]
      resource :rewrite, only: :create
      # The locale segment is :translation_locale, not :locale: a host's around_action that switches the locale
      # from params[:locale] must not read it (a configured translation locale may not be an available one).
      locale = { translation_locale: /[A-Za-z][A-Za-z0-9_-]*/ }
      patch "translations/:translation_locale", to: "translations#update", as: :translation, constraints: locale
      post "translations/:translation_locale/retranslation", to: "translations/retranslations#create", as: :translation_retranslation, constraints: locale
      resources :images, only: %i[create update destroy] do
        resource :move, only: :create, module: :images
      end
    end
  end
  resource :area_detection, only: :create, path: "areas/detection"
  resources :areas, only: %i[index update destroy] do
    scope module: :areas do
      resource :merge, only: :create
      resource :move, only: :create
    end
  end
  resource :board, only: %i[show update]
  resource :sync, only: %i[show create]
  get "assets/:version/:name", to: "/shiplog/frontends#show", as: :frontend, constraints: { version: /[^\/]+/, name: /[a-z_]+\.(css|js)/ }
end
