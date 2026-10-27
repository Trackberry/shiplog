Shiplog::Admin::Engine.routes.draw do
  root to: "entries#index"
  resources :entries, only: %i[index edit update] do
    scope module: :entries do
      resource :approval, only: :create
      resource :discard, only: %i[create destroy]
      resource :rewrite, only: :create
      # An announcement's text as a file to paste elsewhere: ?as=markdown, html or text, in the default locale or
      # ?export_locale= (not :locale, which a host's locale-switching around_action would read; see translations).
      get "export", to: "exports#show", as: :export
      resource :announcement_notification, only: :create
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
  resources :announcements, only: :create
  resource :area_detection, only: :create, path: "areas/detection"
  resource :area_translation, only: :create, path: "areas/translation"
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
