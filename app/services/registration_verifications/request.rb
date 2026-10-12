module RegistrationVerifications
  class Request < ApplicationService
    def self.call(user:, purpose:, channel: nil)
      new(user:, purpose:, channel:).call
    end

    def initialize(user:, purpose:, channel:)
      @user = user
      @purpose = purpose
      @requested_channel = channel.presence
      @channel = channel.presence || "email"
    end

    def call
      case @channel
      when "telegram"
        switching_from_email = @user.otp_verifications.pending.where(purpose: @purpose)
          .any? { |verification| verification.metadata["channel"] == "email" }
        begin
          TelegramGateway::Verifications::Request.call(user: @user, purpose: @purpose,
            skip_resend_delay: switching_from_email)
        rescue TelegramGateway::Client::DeliveryError
          raise if @requested_channel == "telegram"

          EmailVerifications::Request.call(user: @user, purpose: @purpose, skip_resend_delay: true)
        end
      when "email"
        switching_from_telegram = @user.otp_verifications.pending.where(purpose: @purpose)
          .any? { |verification| verification.metadata["channel"] == "telegram" }
        EmailVerifications::Request.call(user: @user, purpose: @purpose,
          skip_resend_delay: switching_from_telegram)
      else
        raise Error, "Verification channel is invalid"
      end
    end
  end
end
