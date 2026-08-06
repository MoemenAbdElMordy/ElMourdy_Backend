module Devices
  class Remove < ApplicationService
    COOLDOWN = 7.days

    def self.call(student_profile:, device:, current_device:, at: Time.current)
      new(student_profile:, device:, current_device:, at:).call
    end

    def initialize(student_profile:, device:, current_device:, at:)
      @student_profile = student_profile
      @device = device
      @current_device = current_device
      @at = at
    end

    def call
      DeviceRegistration.transaction do
        @student_profile.lock!
        validate!
        @device.user_sessions.active.update_all(
          status: UserSession.statuses[:revoked], ended_at: @at, updated_at: @at
        )
        @device.update!(status: :removed, removed_at: @at, last_self_removed_at: @at)
      end
    end

    private

    def validate!
      raise Error, "The current device cannot be removed" if @device == @current_device
      raise Error, "The device is not active" unless @device.active?

      latest_removal = @student_profile.device_registrations.maximum(:last_self_removed_at)
      return if latest_removal.blank? || latest_removal <= COOLDOWN.ago(@at)

      raise Error, "Self-service device removal is available once every seven days"
    end
  end
end
