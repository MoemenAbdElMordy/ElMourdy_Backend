module Api
  class RegistrationsController < ApplicationController
    def create_student
      render_registration(
        Registrations::Create.call(role: :student, attributes: student_params.to_h.symbolize_keys)
      )
    end

    def create_parent
      render_registration(
        Registrations::Create.call(role: :parent, attributes: parent_params.to_h.symbolize_keys)
      )
    end

    def verify
      user = pending_user
      verification = user.otp_verifications.find(verify_params[:verification_id])
      Registrations::Verify.call(user:, verification:, code: verify_params[:code])
      device = register_student_device(user)
      session = Sessions::Start.call(user:, device_registration: device)

      render json: { token: session.raw_token, user: serialize_user(user) }
    end

    def resend
      user = pending_user
      messenger = OtpVerifications::Messenger.build
      result = OtpVerifications::Request.call(
        phone: user.phone_e164,
        purpose: user.student? ? :student_registration : :parent_registration,
        user:,
        messenger:
      )

      render json: verification_payload(user, result.verification, messenger)
    end

    private

    def student_params
      params.require(:registration).permit(
        :name, :phone, :email, :password, :password_confirmation, :birth_date, :parent_phone,
        :governorate, :school, :grade_level
      )
    end

    def parent_params
      params.require(:registration).permit(:name, :phone, :password, :password_confirmation)
    end

    def verify_params
      params.require(:registration).permit(
        :verification_id, :code, :device_fingerprint, :device_name, :browser, :os
      )
    end

    def pending_user
      User.where(phone_verified_at: nil).find(params[:id])
    end

    def render_registration(result)
      render json: verification_payload(result.user, result.verification, nil, result.development_code),
        status: :created
    end

    def verification_payload(user, verification, messenger = nil, development_code = nil)
      code = development_code || (messenger.last_code if messenger.respond_to?(:last_code))
      {
        registration_id: user.id,
        verification_id: verification.id,
        phone: user.phone_e164,
        expires_at: verification.expires_at,
        resend_after_seconds: OtpVerifications::Request::RESEND_DELAY.to_i
      }.tap do |payload|
        payload[:development_code] = code unless Rails.env.production? || code.blank?
      end
    end

    def register_student_device(user)
      return unless user.student?

      fingerprint = verify_params[:device_fingerprint].presence
      raise ApplicationService::Error, "Device fingerprint is required" unless fingerprint

      Devices::Register.call(
        student_profile: user.student_profile,
        fingerprint:,
        attributes: {
          device_name: verify_params[:device_name],
          browser: verify_params[:browser],
          os: verify_params[:os],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        }
      )
    end
  end
end
