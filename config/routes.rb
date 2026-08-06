Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    resource :session, only: %i[create show destroy]
    resources :otp_verifications, only: :create do
      post :verify, on: :member
    end
    post "registrations/student", to: "registrations#create_student"
    post "registrations/parent", to: "registrations#create_parent"
    post "registrations/:id/verify", to: "registrations#verify"
    post "registrations/:id/resend", to: "registrations#resend"
    resource :profile, only: %i[show update] do
      patch :password
    end
    resources :devices, only: %i[index destroy] do
      post :removal_request, on: :member
    end
    resources :academic_years, only: %i[index create update]
    resources :grades, only: :index
    resources :students, only: %i[index show update]
    resources :assistants, only: %i[index create update destroy]
    get "webhooks/whatsapp", to: "whatsapp_webhooks#show"
    post "webhooks/whatsapp", to: "whatsapp_webhooks#create"
  end
end
