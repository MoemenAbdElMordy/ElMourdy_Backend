Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    resource :session, only: %i[create show destroy]
  end
end
