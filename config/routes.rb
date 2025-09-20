# config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  authenticated :user do
    root 'dashboards#show', as: :authenticated_root
  end
  unauthenticated do
    root 'home#index', as: :unauthenticated_root
  end

  # 単語
  resources :words do
    collection do
      post :suggest
    end
  end

  # テスト
  resources :tests, only: [:new, :create, :show] do
    member do
      get  :start
      get  :result
      get  'q/:pos', to: 'test_runs#show',   as: :question
      post 'q/:pos', to: 'test_runs#answer', as: :answer
    end
  end

  resource :dashboards, only: :show

  # API (チャットボット)
  namespace :api do
      post "chat/suggest_word", to: "chat#suggest_word"
  end
end
