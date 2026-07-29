Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    resource :session, only: %i[create show destroy]
    resources :otp_verifications, only: :create do
      post :verify, on: :member
    end
    get "webhooks/whatsapp", to: "whatsapp_webhooks#show"
    post "webhooks/whatsapp", to: "whatsapp_webhooks#create"
  end
end
