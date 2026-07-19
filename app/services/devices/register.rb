module Devices
  class Register < ApplicationService
    MAX_ACTIVE_DEVICES = 3

    def self.call(student_profile:, fingerprint:, attributes: {})
      new(student_profile:, fingerprint:, attributes:).call
    end

    def initialize(student_profile:, fingerprint:, attributes:)
      @student_profile = student_profile
      @digest = Security::DigestValue.call(fingerprint)
      @attributes = attributes.slice(:device_name, :browser, :os, :ip_address, :user_agent)
    end

    def call
      DeviceRegistration.transaction do
        @student_profile.lock!
        device = @student_profile.device_registrations.find_by(device_fingerprint_digest: @digest)
        return reactivate(device) if device

        active_count = @student_profile.device_registrations.active.count
        raise Error, "The student already has three active devices" if active_count >= MAX_ACTIVE_DEVICES

        @student_profile.device_registrations.create!(
          **@attributes,
          device_fingerprint_digest: @digest,
          status: :active,
          last_seen_at: Time.current
        )
      end
    end

    private

    def reactivate(device)
      if !device.active? && @student_profile.device_registrations.active.count >= MAX_ACTIVE_DEVICES
        raise Error, "The student already has three active devices"
      end

      device.update!(**@attributes, status: :active, removed_at: nil, last_seen_at: Time.current)
      device
    end
  end
end
