module OtpVerifications
  class Request < ApplicationService
    Result = Data.define(:verification, :message_id)

    CODE_TTL = 10.minutes
    RESEND_DELAY = 1.minute
    HOURLY_LIMIT = 5

    def self.call(phone:, purpose:, user: nil, messenger: Whatsapp::Client.new, at: Time.current)
      new(phone:, purpose:, user:, messenger:, at:).call
    end

    def initialize(phone:, purpose:, user:, messenger:, at:)
      @phone = PhoneNumbers::Normalize.call(phone)
      @purpose = purpose
      @user = user
      @messenger = messenger
      @at = at
    end

    def call
      enforce_rate_limits!
      code = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
      verification = create_verification(code)
      message_id = deliver(verification, code)

      Result.new(verification:, message_id:)
    end

    private

    def enforce_rate_limits!
      scope = OtpVerification.where(phone_e164: @phone, purpose: @purpose)
      raise Error, "Please wait before requesting another code" if scope.where(created_at: (@at - RESEND_DELAY)..).exists?
      raise Error, "Too many verification codes requested" if scope.where(created_at: (@at - 1.hour)..).count >= HOURLY_LIMIT
    end

    def create_verification(code)
      OtpVerification.create!(
        user: @user,
        phone_e164: @phone,
        purpose: @purpose,
        code_digest: Security::DigestValue.call(code),
        expires_at: @at + CODE_TTL,
        metadata: { channel: "whatsapp" }
      )
    end

    def deliver(verification, code)
      message_id = @messenger.send_otp(phone: @phone, code:)
      verification.update!(metadata: verification.metadata.merge("message_id" => message_id))
      message_id
    rescue Whatsapp::Client::DeliveryError
      verification.update!(status: :failed)
      raise
    end
  end
end
