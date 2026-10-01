Rails.application.routes.draw do
  root "school_classes#index"

  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  get "register/:role", to: "registrations#new", as: :register
  post "register/:role", to: "registrations#create"
  get "password/reset", to: "password_resets#new", as: :new_password_reset
  post "password/reset", to: "password_resets#create"
  get "password/reset/:role/:token", to: "password_resets#edit", as: :edit_password_reset
  patch "password/reset/:role/:token", to: "password_resets#update"
  resources :school_classes do
    post :join, on: :collection
    delete :leave, on: :member
  end
  resources :class_students
  resources :activities
  patch "activities/:activity_id/activity_exercises/reorder", to: "activity_exercises#reorder", as: :reorder_activity_exercises
  resources :exercises do
    post :crossword_preview, on: :collection
  end
  resources :activity_exercises
  resources :exercise_attempts do
    post :memory_game_turn, on: :member
  end
  resources :student_stats

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
