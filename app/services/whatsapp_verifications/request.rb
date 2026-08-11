module WhatsappVerifications
  class Request < ApplicationService
    Result = Data.define(:verification, :whatsapp_url, :client_token)

    TOKEN_TTL = 10.minutes
    RESEND_DELAY = 1.minute
    HOURLY_LIMIT = 5

    def self.call(phone:, purpose:, user:, at: Time.current)
      new(phone:, purpose:, user:, at:).call
    end

    def initialize(phone:, purpose:, user:, at:)
      @phone = PhoneNumbers::Normalize.call(phone)
      @purpose = purpose
      @user = user
      @at = at
    end

    def call
      enforce_rate_limits!
      verification_token = SecureRandom.hex(8).upcase
      client_token = SecureRandom.urlsafe_base64(32)
      verification = create_verification(verification_token, client_token)

      Result.new(
        verification:,
        whatsapp_url: whatsapp_url(verification_token),
        client_token:
      )
    end

    private

    def enforce_rate_limits!
      scope = OtpVerification.where(phone_e164: @phone, purpose: @purpose)
      if scope.where(created_at: (@at - RESEND_DELAY)..).exists?
        raise Error, "Please wait before creating another verification link"
      end
      if scope.where(created_at: (@at - 1.hour)..).count >= HOURLY_LIMIT
        raise Error, "Too many verification links requested"
      end
    end

    def create_verification(verification_token, client_token)
      OtpVerification.transaction do
        OtpVerification.where(
          user: @user,
          phone_e164: @phone,
          purpose: @purpose,
          status: :pending
        ).update_all(status: OtpVerification.statuses.fetch(:expired))

        OtpVerification.create!(
          user: @user,
          phone_e164: @phone,
          purpose: @purpose,
          code_digest: Security::DigestValue.call(verification_token),
          expires_at: @at + TOKEN_TTL,
          metadata: {
            channel: "whatsapp_inbound",
            client_token_digest: Security::DigestValue.call(client_token)
          }
        )
      end
    end

    def whatsapp_url(verification_token)
      business_phone = PhoneNumbers::Normalize.call(ENV.fetch("WHATSAPP_BUSINESS_PHONE_NUMBER"))
      command = @purpose.to_s == "password_reset" ? "RESET" : "VERIFY"
      message = URI.encode_www_form_component("#{command} #{verification_token}")

      "https://wa.me/#{business_phone.delete_prefix('+')}?text=#{message}"
    end
  end
end
