module TelegramGateway
  module Verifications
    class Request < ApplicationService
      Result = Data.define(:verification, :client_token)

      CODE_TTL = 10.minutes
      RESEND_DELAY = 1.minute
      HOURLY_LIMIT = 15

      def self.call(user:, purpose:, at: Time.current, skip_resend_delay: false)
        new(user:, purpose:, at:, skip_resend_delay:).call
      end

      def initialize(user:, purpose:, at:, skip_resend_delay:)
        @user = user
        @purpose = purpose
        @at = at
        @skip_resend_delay = skip_resend_delay
      end

      def call
        enforce_rate_limits!
        code = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
        client_token = SecureRandom.urlsafe_base64(32)
        verification = @user.otp_verifications.create!(
          phone_e164: @user.phone_e164,
          purpose: @purpose,
          code_digest: Security::DigestValue.call(code),
          expires_at: @at + CODE_TTL,
          metadata: { channel: "telegram", client_token_digest: Security::DigestValue.call(client_token) }
        )

        begin
          request_id = Client.new.send_code(phone: @user.phone_e164, code:, ttl: CODE_TTL.to_i)
          verification.update!(metadata: verification.metadata.merge("gateway_request_id" => request_id))
          @user.otp_verifications.where(purpose: @purpose, status: :pending)
            .where.not(id: verification.id).update_all(status: OtpVerification.statuses.fetch(:expired))
        rescue Client::DeliveryError
          verification.update!(status: :failed)
          raise
        end

        Result.new(verification:, client_token:)
      end

      private

      def enforce_rate_limits!
        scope = @user.otp_verifications.where(purpose: @purpose)
        if !@skip_resend_delay && scope.where(created_at: (@at - RESEND_DELAY)..).exists?
          raise Error, "Please wait before requesting another code"
        end
        raise Error, "Too many verification codes requested" if scope.where(created_at: (@at - 1.hour)..).count >= HOURLY_LIMIT
      end
    end
  end
end
