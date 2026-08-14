module EmailVerifications
  class Request < ApplicationService
    Result = Data.define(:verification, :client_token)

    CODE_TTL = 10.minutes
    RESEND_DELAY = 1.minute
    HOURLY_LIMIT = 5

    def self.call(user:, purpose:, at: Time.current)
      new(user:, purpose:, at:).call
    end

    def initialize(user:, purpose:, at:)
      @user = user
      @purpose = purpose
      @at = at
    end

    def call
      raise Error, "An email address is required" if @user.email.blank?

      enforce_rate_limits!
      code = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
      client_token = SecureRandom.urlsafe_base64(32)
      verification = create_verification(code, client_token)
      deliver(verification, code)

      Result.new(verification:, client_token:)
    end

    private

    def enforce_rate_limits!
      scope = @user.otp_verifications.where(purpose: @purpose)
      raise Error, "Please wait before requesting another code" if scope.where(created_at: (@at - RESEND_DELAY)..).exists?
      raise Error, "Too many verification codes requested" if scope.where(created_at: (@at - 1.hour)..).count >= HOURLY_LIMIT
    end

    def create_verification(code, client_token)
      @user.otp_verifications.where(purpose: @purpose, status: :pending).update_all(status: :expired)
      @user.otp_verifications.create!(
        phone_e164: @user.phone_e164,
        purpose: @purpose,
        code_digest: Security::DigestValue.call(code),
        expires_at: @at + CODE_TTL,
        metadata: { channel: "email", client_token_digest: Security::DigestValue.call(client_token) }
      )
    end

    def deliver(verification, code)
      VerificationMailer.with(
        user: @user,
        code:,
        expires_in_minutes: (CODE_TTL / 1.minute).to_i
      ).registration_code.deliver_now
    rescue StandardError => error
      verification.update!(status: :failed)
      Rails.logger.error("Registration email delivery failed: #{error.class}")
      raise Error, "Verification email could not be delivered"
    end
  end
end
