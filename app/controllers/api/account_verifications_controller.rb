module Api
  class AccountVerificationsController < ApplicationController
    before_action :authenticate_user!

    def create
      raise ApplicationService::Error, "Account is already verified" if current_user.phone_verified_at.present?

      result = EmailVerifications::Request.call(user: current_user, purpose: registration_purpose)
      render json: verification_payload(result), status: :created
    end

    def update
      verification = current_user.otp_verifications.find(verification_params[:verification_id])
      Registrations::Verify.call(user: current_user, verification:, code: verification_params[:code])

      render json: { user: serialize_user(current_user.reload) }
    end

    private

    def verification_params
      params.require(:verification).permit(:verification_id, :code)
    end

    def registration_purpose
      current_user.student? ? :student_registration : :parent_registration
    end

    def verification_payload(result)
      {
        verification_id: result.verification.id,
        email_hint: masked_email(current_user.email),
        expires_at: result.verification.expires_at,
        resend_after_seconds: EmailVerifications::Request::RESEND_DELAY.to_i
      }
    end

    def masked_email(email)
      local, domain = email.to_s.split("@", 2)
      return email if local.blank? || domain.blank?

      "#{local.first}#{'*' * [ local.length - 1, 3 ].min}@#{domain}"
    end
  end
end
