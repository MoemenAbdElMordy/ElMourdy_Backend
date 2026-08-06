module Registrations
  class Create < ApplicationService
    Result = Data.define(:user, :verification, :development_code)

    def self.call(role:, attributes:, messenger: OtpVerifications::Messenger.build)
      new(role:, attributes:, messenger:).call
    end

    def initialize(role:, attributes:, messenger:)
      @role = role.to_sym
      @attributes = attributes
      @messenger = messenger
    end

    def call
      validate_role!
      user = create_user_and_profile
      result = OtpVerifications::Request.call(
        phone: user.phone_e164,
        purpose: purpose,
        user:,
        messenger: @messenger
      )

      Result.new(
        user:,
        verification: result.verification,
        development_code: @messenger.respond_to?(:last_code) ? @messenger.last_code : nil
      )
    end

    private

    def validate_role!
      raise Error, "Registration role is invalid" unless %i[student parent].include?(@role)
    end

    def create_user_and_profile
      User.transaction do
        phone = PhoneNumbers::Normalize.call(@attributes.fetch(:phone))
        parent_phone = normalized_parent_phone
        validate_distinct_student_phone!(phone, parent_phone)
        user = User.create!(
          role: @role,
          status: :active,
          name: @attributes.fetch(:name),
          phone_e164: phone,
          phone_display: @attributes.fetch(:phone),
          password: @attributes.fetch(:password),
          password_confirmation: @attributes.fetch(:password_confirmation)
        )

        @role == :student ? create_student_profile(user, parent_phone) : create_parent_profile(user)
        user
      end
    end

    def create_student_profile(user, parent_phone)
      StudentProfile.create!(
        user:,
        birth_date: @attributes.fetch(:birth_date),
        parent_phone_e164: parent_phone,
        governorate: @attributes[:governorate]
      )
    end

    def normalized_parent_phone
      return unless @role == :student

      PhoneNumbers::Normalize.call(@attributes.fetch(:parent_phone))
    end

    def validate_distinct_student_phone!(phone, parent_phone)
      return unless @role == :student && phone == parent_phone

      raise Error, "Student and parent phone numbers must be different"
    end

    def create_parent_profile(user)
      unless StudentProfile.exists?(parent_phone_e164: user.phone_e164)
        raise Error, "No student is registered with this parent phone number"
      end

      ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    end

    def purpose
      @role == :student ? :student_registration : :parent_registration
    end
  end
end
