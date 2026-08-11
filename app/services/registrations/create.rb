module Registrations
  class Create < ApplicationService
    Result = Data.define(:user, :verification, :whatsapp_url, :client_token)

    def self.call(role:, attributes:)
      new(role:, attributes:).call
    end

    def initialize(role:, attributes:)
      @role = role.to_sym
      @attributes = attributes
    end

    def call
      validate_role!
      user = create_user_and_profile
      result = WhatsappVerifications::Request.call(
        phone: user.phone_e164,
        purpose: purpose,
        user:
      )

      Result.new(
        user:,
        verification: result.verification,
        whatsapp_url: result.whatsapp_url,
        client_token: result.client_token
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
          email: @attributes[:email],
          password: @attributes.fetch(:password),
          password_confirmation: @attributes.fetch(:password_confirmation)
        )

        if @role == :student
          profile = create_student_profile(user, parent_phone)
          create_student_enrollment(profile)
        else
          create_parent_profile(user)
        end
        user
      end
    end

    def create_student_profile(user, parent_phone)
      StudentProfile.create!(
        user:,
        birth_date: @attributes.fetch(:birth_date),
        parent_phone_e164: parent_phone,
        governorate: @attributes[:governorate],
        school: @attributes[:school]
      )
    end

    def create_student_enrollment(profile)
      year = AcademicYear.active.order(starts_on: :desc).first
      raise Error, "No active academic year is available" unless year

      grade = Grade.enabled.find_by(level: @attributes.fetch(:grade_level))
      raise Error, "The selected grade is invalid" unless grade

      StudentEnrollment.create!(
        student_profile: profile,
        academic_year: year,
        grade:,
        enrolled_at: Time.current,
        status: :active
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
