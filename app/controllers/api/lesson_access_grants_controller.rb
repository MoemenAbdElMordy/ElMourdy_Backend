module Api
  class LessonAccessGrantsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_codes") }

    def index
      student = User.student.find(params.require(:student_user_id)).student_profile
      grants = student.lesson_access_grants.includes(:lesson, :academic_year).order(created_at: :desc)
      render json: { access_grants: grants.map { |grant| serialize(grant) } }
    end

    def create
      attributes = grant_params
      student = User.student.find(attributes.fetch(:student_user_id)).student_profile
      lesson = Lesson.find(attributes.fetch(:lesson_id))
      year = AcademicYear.find(attributes.fetch(:academic_year_id))
      enrollment = student.student_enrollments.active.find_by(academic_year: year)
      raise ApplicationService::Error, "The student is not enrolled in this academic year" unless enrollment

      grant = LessonAccessGrant.find_or_initialize_by(student_profile: student, lesson:, academic_year: year)
      grant.update!(source: :manual, activation_code: nil, expires_on: attributes.fetch(:expires_on), status: :active)
      render json: { access_grant: serialize(grant) }, status: :created
    end

    def update
      grant = LessonAccessGrant.find(params[:id])
      grant.update!(status: params.require(:lesson_access_grant).fetch(:status))
      render json: { access_grant: serialize(grant) }
    end

    private

    def grant_params
      params.require(:lesson_access_grant).permit(:student_user_id, :lesson_id, :academic_year_id, :expires_on)
    end

    def serialize(grant)
      { id: grant.id, student_user_id: grant.student_profile.user_id, lesson_id: grant.lesson_id, lesson: grant.lesson.title, academic_year_id: grant.academic_year_id, academic_year: grant.academic_year.name, source: grant.source, expires_on: grant.expires_on, status: grant.status }
    end
  end
end
