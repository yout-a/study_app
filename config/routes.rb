# config/routes.rb
Rails.application.routes.draw do
  get 'tests/new'
  get 'tests/show'
  devise_for :users

  authenticated :user do
    root "dashboards#show", as: :authenticated_root
  end
  unauthenticated { root "home#index", as: :unauthenticated_root }

  resources :words  
  resources :tests, only: [:new, :create, :show] do
    member do
      get  :start
      get  :result         # ← 追加
      get  'q/:pos', to: 'test_runs#show',   as: :question
      post 'q/:pos', to: 'test_runs#answer', as: :answer
    end
  end
    resource  :dashboards, only: :show
end
