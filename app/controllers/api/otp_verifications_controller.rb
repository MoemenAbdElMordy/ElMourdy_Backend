module Api
  class OtpVerificationsController < ApplicationController
    def create
      result = OtpVerifications::Request.call(
        phone: create_params[:phone],
        purpose: create_params[:purpose]
      )

      render json: serialize(result.verification), status: :created
    end

    def verify
      verification = OtpVerification.find(params[:id])
      OtpVerifications::Verify.call(verification:, code: verify_params[:code])

      render json: serialize(verification.reload)
    end

    private

    def create_params
      params.require(:otp_verification).permit(:phone, :purpose)
    end

    def verify_params
      params.require(:otp_verification).permit(:code)
    end

    def serialize(verification)
      {
        id: verification.id,
        phone: verification.phone_e164,
        purpose: verification.purpose,
        status: verification.status,
        expires_at: verification.expires_at
      }
    end
  end
end
