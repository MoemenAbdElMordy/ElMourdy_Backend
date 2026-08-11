module Api
  class AssistantsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_teacher!

    def index
      render json: { assistants: assistant_users.map { |user| serialize_assistant(user) }, permission_keys: AssistantPermission::KEYS }
    end

    def create
      user = User.transaction do
        created = User.create!(assistant_user_params.merge(role: :assistant, status: :active, phone_verified_at: Time.current))
        profile = AssistantProfile.create!(user: created, title: assistant_params[:title], can_login: true)
        sync_permissions(profile)
        created
      end
      render json: { assistant: serialize_assistant(user) }, status: :created
    end

    def update
      user = assistant_user
      User.transaction do
        user.update!(assistant_update_params)
        user.assistant_profile.update!(title: assistant_params[:title]) if assistant_params.key?(:title)
        sync_permissions(user.assistant_profile) if assistant_params.key?(:permissions)
        revoke_sessions(user) if !user.active? || assistant_params[:password].present?
      end
      render json: { assistant: serialize_assistant(user) }
    end

    def destroy
      user = assistant_user
      user.update!(status: :archived)
      revoke_sessions(user)
      head :no_content
    end

    private

    def assistant_users
      User.assistant.includes(assistant_profile: :assistant_permissions).order(:name)
    end

    def assistant_user
      assistant_users.find(params[:id])
    end

    def assistant_params
      params.require(:assistant).permit(:name, :phone, :email, :title, :password, :password_confirmation, :status, permissions: [])
    end

    def assistant_user_params
      assistant_params.slice(:name, :email, :password, :password_confirmation).merge(
        phone_e164: PhoneNumbers::Normalize.call(assistant_params.fetch(:phone)),
        phone_display: assistant_params.fetch(:phone)
      )
    end

    def assistant_update_params
      attributes = assistant_params.slice(:name, :email, :status)
      if assistant_params[:password].present?
        attributes[:password] = assistant_params[:password]
        attributes[:password_confirmation] = assistant_params[:password_confirmation]
      end
      attributes
    end

    def sync_permissions(profile)
      keys = Array(assistant_params[:permissions]) & AssistantPermission::KEYS
      AssistantPermission::KEYS.each do |key|
        permission = profile.assistant_permissions.find_or_initialize_by(permission_key: key)
        permission.update!(enabled: keys.include?(key))
      end
    end

    def serialize_assistant(user)
      profile = user.assistant_profile
      {
        id: user.id,
        name: user.name,
        phone: user.phone_e164,
        email: user.email,
        title: profile.title,
        status: user.status,
        permissions: profile.assistant_permissions.select(&:enabled?).map(&:permission_key),
        created_at: user.created_at
      }
    end

    def revoke_sessions(user)
      user.user_sessions.active.update_all(status: UserSession.statuses[:revoked], ended_at: Time.current)
    end
  end
end
