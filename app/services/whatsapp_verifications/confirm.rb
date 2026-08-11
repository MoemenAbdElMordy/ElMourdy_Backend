module WhatsappVerifications
  class Confirm < ApplicationService
    TOKEN_PATTERN = /\A(VERIFY|RESET)\s+([A-F0-9]{16})\z/i

    def self.call(phone:, message:, message_id: nil, at: Time.current)
      new(phone:, message:, message_id:, at:).call
    end

    def initialize(phone:, message:, message_id:, at:)
      @phone = PhoneNumbers::Normalize.call(phone)
      @message = message.to_s.strip
      @message_id = message_id
      @at = at
    end

    def call
      match = @message.match(TOKEN_PATTERN)
      return unless match

      command, token = match.captures
      verification = matching_verification(command, token)
      return unless verification

      confirm!(verification)
    end

    private

    def matching_verification(command, token)
      digest = Security::DigestValue.call(token.upcase)
      scope = OtpVerification.pending
        .where(phone_e164: @phone)
        .where("expires_at > ?", @at)
        .order(created_at: :desc)
      scope = command.casecmp("RESET").zero? ? scope.password_reset : scope.where.not(purpose: :password_reset)
      scope.find do |verification|
          verification.metadata["channel"] == "whatsapp_inbound" &&
            ActiveSupport::SecurityUtils.secure_compare(verification.code_digest, digest)
      end
    end

    def confirm!(verification)
      OtpVerification.transaction do
        verification.lock!
        return unless verification.pending? && verification.expires_at > @at

        user = verification.user
        return unless user && user.phone_e164 == @phone
        return if verification.password_reset? && (!user.active? || user.phone_verified_at.blank?)

        verification.update!(
          status: :verified,
          verified_at: @at,
          metadata: verification.metadata.merge("inbound_message_id" => @message_id).compact
        )
        unless verification.password_reset?
          user.lock!
          user.update!(phone_verified_at: @at)
          ParentLinks::Sync.call(parent_profile: user.parent_profile, at: @at) if user.parent?
        end
      end

      verification
    end
  end
end
