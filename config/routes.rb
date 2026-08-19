Rails.application.routes.draw do
  root "api_root#show"
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    resource :session, only: %i[create show destroy]
    resource :account_verification, only: %i[create update]
    resources :otp_verifications, only: :create do
      post :verify, on: :member
    end
    post "registrations/student", to: "registrations#create_student"
    post "registrations/parent", to: "registrations#create_parent"
    post "registrations/:id/verify", to: "registrations#verify"
    post "registrations/:id/resend", to: "registrations#resend"
    post "registrations/:id/status", to: "registrations#status"
    post "registrations/:id/complete", to: "registrations#complete"
    resources :password_resets, only: %i[create update] do
      post :status, on: :member
    end
    resource :profile, only: %i[show update] do
      patch :password
    end
    resources :devices, only: %i[index destroy] do
      post :removal_request, on: :member
    end
    resources :academic_years, only: %i[index create update]
    post "academic_years/:id/copy_content", to: "academic_years#copy_content"
    post "academic_years/:id/rollover_students", to: "academic_years#rollover_students"
    resources :grades, only: :index
    resources :students, only: %i[index show update]
    resources :parents, only: %i[index show update] do
      patch :password, on: :member
    end
    patch "students/:id/enrollment", to: "students#update_enrollment"
    patch "students/:id/password", to: "students#reset_password"
    patch "students/:id/parent_phone", to: "students#update_parent_phone"
    delete "students/:id/devices/:device_id", to: "students#destroy_device"
    get "students/:id/preview", to: "student_previews#show"
    resources :assistants, only: %i[index create update destroy]
    resource :dashboard, only: :show
    resource :management_report, only: :show
    resources :audit_logs, only: :index
    resources :free_lectures, only: :index
    get "curriculum", to: "curriculum#show"
    resources :curriculum_locations, only: :index
    resources :branches, only: %i[create update destroy] do
      patch :reorder, on: :collection
    end
    resources :chapters, only: %i[create update destroy] do
      patch :reorder, on: :collection
    end
    resources :lessons, only: %i[create update destroy] do
      patch :reorder, on: :collection
    end
    resources :lectures, only: %i[create update destroy] do
      patch :reorder, on: :collection
      resource :thumbnail, only: %i[show update destroy], controller: :lecture_thumbnails
      resource :video_upload, only: %i[create] do
        put :content
        post :complete
      end
      resource :video_playback, only: :show
    end
    resources :video_assets, only: %i[show destroy] do
      post :retry_processing, on: :member
    end
    resources :lecture_watch_events, only: :update
    get "video_delivery/:video_asset_id/:token/*path", to: "video_delivery#show", as: :video_delivery,
      constraints: { token: /[^\/]+/ }, format: false
    resources :activation_code_batches, only: %i[index create] do
      get :export, on: :member
    end
    resources :activation_codes, only: %i[update destroy] do
      post :redeem, on: :collection
    end
    resources :lesson_access_grants, only: %i[index create update]
    resources :exams, only: %i[index show create update]
    resources :exam_attempts, only: %i[index show] do
      post :submit, on: :member
    end
    post "exams/:exam_id/attempts", to: "exam_attempts#create"
    resources :announcements, only: %i[index create update destroy]
    resources :support_requests, only: %i[index create show] do
      post :review, on: :member
    end
    get "webhooks/whatsapp", to: "whatsapp_webhooks#show"
    post "webhooks/whatsapp", to: "whatsapp_webhooks#create"
  end
end
