module Registrations
  class Verify < ApplicationService
    def self.call(user:, verification:, code:, at: Time.current)
      new(user:, verification:, code:, at:).call
    end

    def initialize(user:, verification:, code:, at:)
      @user = user
      @verification = verification
      @code = code
      @at = at
    end

    def call
      validate_verification!

      User.transaction do
        OtpVerifications::Verify.call(verification: @verification, code: @code, at: @at)
        @user.lock!
        @user.update!(phone_verified_at: @at)
        ParentLinks::Sync.call(parent_profile: @user.parent_profile, at: @at) if @user.parent?
      end

      @user
    end

    private

    def validate_verification!
      expected_purpose = @user.student? ? "student_registration" : "parent_registration"
      valid = @verification.user_id == @user.id &&
        @verification.phone_e164 == @user.phone_e164 &&
        @verification.purpose == expected_purpose
      raise Error, "Verification does not belong to this registration" unless valid
    end
  end
end
