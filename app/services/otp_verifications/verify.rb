module OtpVerifications
  class Verify < ApplicationService
    MAX_ATTEMPTS = 5

    def self.call(verification:, code:, at: Time.current)
      new(verification:, code:, at:).call
    end

    def initialize(verification:, code:, at:)
      @verification = verification
      @code = code.to_s
      @at = at
    end

    def call
      error_message = nil

      OtpVerification.transaction do
        @verification.lock!
        error_message = validation_error

        if error_message.nil?
          @verification.attempts_count += 1
          if valid_code?
            mark_verified!
          else
            @verification.status = :failed if @verification.attempts_count >= MAX_ATTEMPTS
            @verification.save!
            error_message = "Verification code is invalid"
          end
        end
      end

      raise Error, error_message if error_message

      @verification
    end

    private

    def validation_error
      return "Verification code is no longer active" unless @verification.pending?
      if @verification.expires_at <= @at
        @verification.update!(status: :expired)
        return "Verification code has expired"
      end
      if @verification.attempts_count >= MAX_ATTEMPTS
        @verification.update!(status: :failed)
        "Verification code is no longer active"
      end
    end

    def valid_code?
      return false unless @code.match?(/\A\d{6}\z/)

      ActiveSupport::SecurityUtils.secure_compare(
        Security::DigestValue.call(@code),
        @verification.code_digest
      )
    end

    def mark_verified!
      @verification.update!(status: :verified, verified_at: @at)
      @verification
    end
  end
end
