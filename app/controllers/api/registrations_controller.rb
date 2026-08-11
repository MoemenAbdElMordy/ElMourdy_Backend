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

    def status
      user = registration_user
      verification = registration_verification(user)
      validate_client_token!(verification)
      expire_verification!(verification)

      render json: { status: verification.reload.status, expires_at: verification.expires_at }
    end

    def complete
      user = registration_user
      verification = registration_verification(user)
      validate_client_token!(verification)
      unless verification.verified? && user.phone_verified_at.present?
        raise ApplicationService::Error, "Phone verification is not complete"
      end

      device = register_student_device(user, complete_params)
      session = Sessions::Start.call(user:, device_registration: device)

      render json: { token: session.raw_token, user: serialize_user(user) }
    end

    def resend
      user = pending_user
      result = WhatsappVerifications::Request.call(
        phone: user.phone_e164,
        purpose: user.student? ? :student_registration : :parent_registration,
        user:
      )

      render json: verification_payload(user, result)
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

    def status_params
      params.require(:registration).permit(:verification_id, :client_token)
    end

    def complete_params
      params.require(:registration).permit(
        :verification_id, :client_token, :device_fingerprint, :device_name, :browser, :os
      )
    end

    def pending_user
      User.where(phone_verified_at: nil).find(params[:id])
    end

    def registration_user
      User.where(role: %i[student parent]).find(params[:id])
    end

    def render_registration(result)
      render json: verification_payload(result.user, result),
        status: :created
    end

    def verification_payload(user, result)
      {
        registration_id: user.id,
        verification_id: result.verification.id,
        phone: user.phone_e164,
        expires_at: result.verification.expires_at,
        resend_after_seconds: WhatsappVerifications::Request::RESEND_DELAY.to_i,
        verification_method: "whatsapp_inbound",
        whatsapp_url: result.whatsapp_url,
        client_token: result.client_token
      }
    end

    def registration_verification(user)
      user.otp_verifications.find(status_params[:verification_id] || complete_params[:verification_id])
    end

    def validate_client_token!(verification)
      provided = (status_params[:client_token] || complete_params[:client_token]).to_s
      expected = verification.metadata["client_token_digest"].to_s
      valid = expected.present? && Security::DigestValue.call(provided).bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(Security::DigestValue.call(provided), expected)
      raise ApplicationService::Error, "Registration verification token is invalid" unless valid
    end

    def expire_verification!(verification)
      verification.update!(status: :expired) if verification.pending? && verification.expires_at <= Time.current
    end

    def register_student_device(user, permitted_params = verify_params)
      return unless user.student?

      fingerprint = permitted_params[:device_fingerprint].presence
      raise ApplicationService::Error, "Device fingerprint is required" unless fingerprint

      Devices::Register.call(
        student_profile: user.student_profile,
        fingerprint:,
        attributes: {
          device_name: permitted_params[:device_name],
          browser: permitted_params[:browser],
          os: permitted_params[:os],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        }
      )
    end
  end
end
