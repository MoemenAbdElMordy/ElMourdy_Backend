module Sessions
  class Start < ApplicationService
    Result = Data.define(:raw_token, :session)

    def self.call(user:, device_registration: nil, at: Time.current)
      new(user:, device_registration:, at:).call
    end

    def initialize(user:, device_registration:, at:)
      @user = user
      @device_registration = device_registration
      @at = at
    end

    def call
      UserSession.transaction do
        @user.lock!
        validate_device!
        revoke_previous_student_sessions!

        raw_token = SecureRandom.urlsafe_base64(48)
        session = @user.user_sessions.create!(
          device_registration: @device_registration,
          session_token_digest: Security::DigestValue.call(raw_token),
          started_at: @at,
          last_seen_at: @at,
          status: :active
        )
        Result.new(raw_token:, session:)
      end
    end

    private

    def validate_device!
      return unless @user.student?

      profile = @user.student_profile
      valid = @device_registration&.active? && @device_registration.student_profile_id == profile&.id
      raise Error, "An active registered device is required" unless valid
    end

    def revoke_previous_student_sessions!
      return unless @user.student?

      @user.user_sessions.active.update_all(status: UserSession.statuses[:revoked], ended_at: @at)
    end
  end
end
