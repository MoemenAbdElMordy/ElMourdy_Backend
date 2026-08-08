module ActivationCodes
  class Redeem < ApplicationService
    def self.call(raw_code:, student_profile:, at: Time.current)
      new(raw_code:, student_profile:, at:).call
    end

    def initialize(raw_code:, student_profile:, at:)
      @digest = Security::DigestValue.call(raw_code.strip.upcase)
      @student_profile = student_profile
      @at = at
    end

    def call
      ActivationCode.transaction do
        code = ActivationCode.lock.find_by!(code_digest: @digest)
        batch = code.activation_code_batch

        raise Error, "Activation code is not redeemable" unless code.unused? && code.deleted_at.nil?
        raise Error, "Activation code has expired" if batch.expires_on < @at.to_date
        enrollment = @student_profile.student_enrollments.active.find_by(academic_year: batch.academic_year)
        raise Error, "Activation code is not valid for the student's grade" unless enrollment&.grade_id == batch.grade_id
        grant = LessonAccessGrant.find_or_initialize_by(
          student_profile: @student_profile,
          lesson: batch.lesson,
          academic_year: batch.academic_year
        )
        if grant.persisted? && grant.active? && grant.expires_on >= @at.to_date
          raise Error, "The student already has access to this lesson"
        end

        code.update!(
          status: :redeemed,
          redeemed_by_student_profile: @student_profile,
          redeemed_at: @at
        )

        grant.update!(
          activation_code: code,
          source: :code,
          expires_on: batch.expires_on,
          status: :active
        )
        grant
      end
    rescue ActiveRecord::RecordNotFound
      raise Error, "Activation code is invalid"
    rescue ActiveRecord::RecordNotUnique
      raise Error, "The student already has access to this lesson"
    end
  end
end
