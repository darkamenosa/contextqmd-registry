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
      resources :projects, only: [ :index ]
      resource :settings, only: [ :show, :update, :destroy ]
      resource :billing, only: :show
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
      resources :customers, only: [ :index, :show ], constraints: { id: /\d+/ } do
        scope module: :customers do
          resource :account_reactivation, only: :create
          resource :suspension, only: [ :create, :destroy ]
          resource :staff_access, only: [ :create, :destroy ]
        end
      end
      namespace :customers do
        resource :bulk_suspension, only: [ :create, :destroy ]
      end
      resources :webhooks, only: [ :index ]

      namespace :analytics do
        resource :live, only: :show
        resources :reports, only: [ :index ]
      end

      resource :settings, only: :show
      namespace :settings do
        resource :team, only: :show
        resource :billing, only: :show
      end
    end
    mount MissionControl::Jobs::Engine, at: "/admin/jobs" if defined?(MissionControl::Jobs::Engine)
  end
  get "admin", to: redirect("/admin/dashboard")

  # Redirect to localhost from 127.0.0.1
  constraints(host: "127.0.0.1") do
    get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
  end

  # Public pages
  root "pages#home"
  get "about", to: "pages#about"
  get "pricing", to: "pages#pricing"
  get "privacy", to: "pages#privacy"
  get "terms", to: "pages#terms"
  get "contact", to: "pages#contact"

  # Error pages
  get "errors/:status", to: "errors#show", as: :error

  get "up" => "rails/health#show", as: :rails_health_check
end
