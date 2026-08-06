module Api
  class SessionsController < ApplicationController
    before_action :authenticate_user!, only: %i[show destroy]

    def create
      user = User.available_for_login.find_by(phone_e164: normalized_phone)
      return render_invalid_credentials unless user&.authenticate(session_params[:password])

      device = register_student_device(user)
      result = Sessions::Start.call(user:, device_registration: device)
      user.update_column(:last_login_at, Time.current)

      render json: { token: result.raw_token, user: serialize_user(user) }, status: :created
    end

    def show
      render json: { user: serialize_user(current_user) }
    end

    def destroy
      current_session.update!(status: :ended, ended_at: Time.current)
      head :no_content
    end

    private

    def session_params
      params.require(:session).permit(
        :phone, :password, :device_fingerprint, :device_name, :browser, :os
      )
    end

    def normalized_phone
      PhoneNumbers::Normalize.call(session_params[:phone])
    rescue ApplicationService::Error
      nil
    end

    def register_student_device(user)
      return unless user.student?

      fingerprint = session_params[:device_fingerprint].presence
      raise ApplicationService::Error, "Device fingerprint is required" unless fingerprint

      Devices::Register.call(
        student_profile: user.student_profile,
        fingerprint:,
        attributes: {
          device_name: session_params[:device_name],
          browser: session_params[:browser],
          os: session_params[:os],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        }
      )
    end

    def render_invalid_credentials
      render json: {
        error: { code: "invalid_credentials", message: "Phone number or password is incorrect" }
      }, status: :unauthorized
    end
  end
end
