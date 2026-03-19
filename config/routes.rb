Rails.application.routes.draw do
  devise_for :identities,
    path: "",
    path_names: { sign_in: "login", sign_out: "logout", registration: "register", sign_up: "" },
    controllers: {
      sessions: "identities/sessions",
      registrations: "identities/registrations",
      passwords: "identities/passwords",
      omniauth_callbacks: "identities/omniauth_callbacks"
    }

  # App (authentication handled by controllers)
  scope "app/:account_id", constraints: { account_id: /\d+/ } do
    namespace :app, path: "" do
      resource :dashboard, only: :show
      resources :crawl_requests, only: [ :new, :create ], path: "crawl"
      resource :settings, only: [ :show, :update, :destroy ]
    end
    get "access_tokens", to: "app/access_tokens#index", as: :scoped_app_access_tokens
    post "access_tokens", to: "app/access_tokens#create"
    delete "access_tokens/:id", to: "app/access_tokens#destroy", as: :scoped_app_access_token
    # /app/:account_id → redirect to dashboard
    get "/", to: redirect { |params, _| "/app/#{params[:account_id]}/dashboard" }
  end
  get "app", to: "app/menus#show", as: :app
  namespace :app, path: "app" do
    resources :access_tokens, only: [ :index, :create, :destroy ]
    resource :account_reactivation, only: :create
  end

  # Admin (authorization handled by Admin::BaseController)
  authenticate :identity, ->(identity) { identity.staff? } do
    namespace :admin do
      resource :dashboard, only: :show
      resources :users, only: [ :index, :show ], constraints: { id: /\d+/ } do
        scope module: :users do
          resource :account_reactivation, only: :create
          resource :suspension, only: [ :create, :destroy ]
          resource :staff_access, only: [ :create, :destroy ]
        end
      end
      namespace :users do
        resource :bulk_suspension, only: [ :create, :destroy ]
      end
      resources :libraries, only: [ :index, :show, :edit, :update, :destroy ] do
        scope module: :libraries do
          resource :recrawl, only: :create
          resource :default_version, only: :update
          resources :versions, only: [ :show, :update, :destroy ] do
            resources :pages, only: [ :index, :show, :edit, :update, :destroy ]
          end
        end
      end
      resources :crawl_requests, only: [ :index, :show, :destroy ] do
        scope module: :crawl_requests do
          resource :cancellation, only: :create
          resource :retry, only: :create
        end
      end
      resources :proxy_configs
      resources :webhooks, only: [ :index ]

      namespace :analytics do
        resource :live, only: :show
        resources :reports, only: [ :index ]
      end

      resource :settings, only: :show
      namespace :settings do
        resource :team, only: :show
      end
    end
    mount MissionControl::Jobs::Engine, at: "/admin/jobs" if defined?(MissionControl::Jobs::Engine)
  end
  get "admin", to: redirect("/admin/dashboard")

  # Redirect to localhost from 127.0.0.1
  constraints(host: "127.0.0.1") do
    get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
  end

  # Library browsing (public) + submission (authenticated)
  resources :libraries, only: [ :index, :new, :create ], param: :slug do
    member do
      get "", action: :show
      get "versions/:version/pages/*page_uid", to: "libraries/pages#show", as: :page_detail, version: /[^\/]+/, format: false
    end
  end

  # Crawl requests: index is public, new redirects to app layout
  resources :crawl_requests, only: [ :index, :new ], path: "crawl"

  # Rankings
  get "rankings", to: "rankings#index"

  # Public pages
  root "homepages#show"
  %w[about privacy terms contact].each do |slug|
    get slug, to: "pages#show", defaults: { id: slug }
  end

  # Error pages
  get "errors/:status", to: "errors#show", as: :error

  # API v1 (token-authenticated, JSON-only)
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      get "capabilities", to: "capabilities#show"
      resources :libraries, only: [ :index, :show ], param: :slug do
        get "versions", to: "versions#index", on: :member
        get "versions/:version/manifest", to: "manifests#show", on: :member, version: /[^\/]+/
        get "versions/:version/page-index", to: "page_index#index", on: :member, version: /[^\/]+/
        get "versions/:version/pages/*page_uid", to: "page_index#show", on: :member, version: /[^\/]+/, format: false
        get "versions/:version/bundles/:profile", to: "bundles#show", on: :member, version: /[^\/]+/
        post "versions/:version/query", to: "query_docs#create", on: :member, version: /[^\/]+/
      end
      post "resolve", to: "resolve#create"
      post "crawl", to: "crawl_requests#create"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # Sitemap index + paginated sub-sitemaps
  get "sitemap.xml", to: "sitemaps#index", defaults: { format: :xml }
  get "sitemaps/static.xml", to: "sitemaps#static_pages", defaults: { format: :xml }
  get "sitemaps/libraries/:page", to: "sitemaps#libraries", defaults: { format: :xml }, constraints: { page: /\d+/ }
  get "sitemaps/pages/:page", to: "sitemaps#pages", defaults: { format: :xml }, constraints: { page: /\d+/ }

  # Catch-all: render Inertia 404 instead of static public/404.html
  get "*unmatched", to: "errors#show", defaults: { status: "404" },
    constraints: ->(req) { req.format.html? }
end
