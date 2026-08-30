module ActivationCodes
  class Redeem < ApplicationService
    def self.call(raw_code:, student_profile:, lecture: nil, at: Time.current)
      new(raw_code:, student_profile:, lecture:, at:).call
    end

    def initialize(raw_code:, student_profile:, lecture:, at:)
      @digest = Security::DigestValue.call(raw_code.strip.upcase)
      @student_profile = student_profile
      @lecture = lecture
      @at = at
    end

    def call
      ActivationCode.transaction do
        code = ActivationCode.lock.find_by!(code_digest: @digest)
        batch = code.activation_code_batch

        raise Error, "Activation code is not redeemable" unless code.unused? && code.deleted_at.nil?
        raise Error, "Activation code has expired" if batch.expires_on < @at.to_date

        batch.generic? ? redeem_generic_code(code, batch) : redeem_legacy_code(code, batch)
      end
    rescue ActiveRecord::RecordNotFound
      raise Error, "Activation code is invalid"
    rescue ActiveRecord::RecordNotUnique
      raise Error, "The student already has access to this lecture"
    end

    private

    def redeem_generic_code(code, batch)
      raise Error, "A lecture must be selected before redeeming this code" unless @lecture

      enrollment = @student_profile.student_enrollments.active.includes(:academic_year).order(enrolled_at: :desc).first
      eligible_lessons = @lecture.all_lessons.joins(chapter: :branch).where(
        branches: { academic_year_id: enrollment&.academic_year_id, grade_id: enrollment&.grade_id }
      )
      raise Error, "This lecture is not available for the student's grade" unless enrollment && eligible_lessons.exists?
      if @lecture.is_free? || eligible_lessons.where(is_free: true).exists? || existing_access?(eligible_lessons, enrollment)
        raise Error, "The student already has access to this lecture"
      end

      grant = LectureAccessGrant.find_or_initialize_by(
        student_profile: @student_profile,
        lecture: @lecture,
        academic_year: enrollment.academic_year
      )
      if grant.persisted? && grant.active? && grant.expires_on >= @at.to_date
        raise Error, "The student already has access to this lecture"
      end

      redeem_code!(code)
      grant.update!(activation_code: code, expires_on: batch.expires_on, status: :active)
      grant
    end

    def redeem_legacy_code(code, batch)
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

      redeem_code!(code)
      grant.update!(activation_code: code, source: :code, expires_on: batch.expires_on, status: :active)
      grant
    end

    def existing_access?(eligible_lessons, enrollment)
      @student_profile.lesson_access_grants.currently_active.exists?(
        lesson_id: eligible_lessons.select(:id), academic_year_id: enrollment.academic_year_id
      ) || @student_profile.lecture_access_grants.currently_active.exists?(
        lecture_id: @lecture.id, academic_year_id: enrollment.academic_year_id
      )
    end

    def redeem_code!(code)
      code.update!(status: :redeemed, redeemed_by_student_profile: @student_profile, redeemed_at: @at)
    end
  end
end
