module Api
  class PasswordResetsController < ApplicationController
    def create
      email = create_params[:email].to_s.strip.downcase
      user = User.available_for_login.find_by("LOWER(email) = ?", email)
      raise ApplicationService::Error, "No active account uses this email address" unless user

      result = EmailVerifications::Request.call(user:, purpose: :password_reset)

      render json: verification_payload(result), status: :created
    end

    def verify
      verification = password_reset_verification
      validate_client_token!(verification)
      OtpVerifications::Verify.call(verification:, code: verify_params[:code])

      render json: { status: verification.reload.status, expires_at: verification.expires_at }
    end

    def status
      verification = password_reset_verification
      validate_client_token!(verification)
      expire_verification!(verification)

      render json: { status: verification.reload.status, expires_at: verification.expires_at }
    end

    def update
      verification = password_reset_verification
      validate_client_token!(verification)

      OtpVerification.transaction do
        verification.lock!
        expire_verification!(verification)
        raise ApplicationService::Error, "Email verification is not complete" unless verification.verified?

        user = verification.user
        raise ApplicationService::Error, "Password reset could not be completed" unless user&.active?

        user.update!(
          password: update_params[:password],
          password_confirmation: update_params[:password_confirmation]
        )
        user.user_sessions.active.update_all(
          status: UserSession.statuses.fetch(:ended),
          ended_at: Time.current,
          updated_at: Time.current
        )
        verification.consumed!
      end

      head :no_content
    end

    private

    def create_params
      params.require(:password_reset).permit(:email)
    end

    def verify_params
      params.require(:password_reset).permit(:client_token, :code)
    end

    def client_params
      params.require(:password_reset).permit(:client_token)
    end

    def update_params
      params.require(:password_reset).permit(:client_token, :password, :password_confirmation)
    end

    def password_reset_verification
      OtpVerification.password_reset.find(params[:id])
    end

    def validate_client_token!(verification)
      provided = (client_params[:client_token] || update_params[:client_token]).to_s
      expected = verification.metadata["client_token_digest"].to_s
      provided_digest = Security::DigestValue.call(provided)
      valid = expected.present? && provided_digest.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided_digest, expected)
      raise ApplicationService::Error, "Password reset token is invalid" unless valid
    end

    def expire_verification!(verification)
      return unless (verification.pending? || verification.verified?) && verification.expires_at <= Time.current

      verification.update!(status: :expired)
    end

    def verification_payload(result)
      {
        password_reset_id: result.verification.id,
        expires_at: result.verification.expires_at,
        resend_after_seconds: EmailVerifications::Request::RESEND_DELAY.to_i,
        verification_method: "email_code",
        client_token: result.client_token
      }
    end
  end
end
