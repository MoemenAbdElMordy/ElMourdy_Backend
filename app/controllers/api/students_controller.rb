module Api
  class StudentsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_students") }

    def index
      users = User.student.includes(student_profile: { student_enrollments: %i[grade academic_year] })
      users = users.where(status: params[:status]) if User.statuses.key?(params[:status])
      users = users.where("users.name LIKE :query OR users.phone_e164 LIKE :query", query: "%#{params[:query]}%") if params[:query].present?
      users = users.joins(student_profile: :student_enrollments).where(student_enrollments: { grade_id: params[:grade_id] }).distinct if params[:grade_id].present?

      render json: { students: users.order(created_at: :desc).map { |user| serialize_student(user) } }
    end

    def show
      user = student_user
      render json: { student: serialize_student(user, detailed: true) }
    end

    def update
      user = student_user
      user.update!(status: student_params.fetch(:status))
      user.user_sessions.active.update_all(status: UserSession.statuses[:revoked], ended_at: Time.current) unless user.active?
      render json: { student: serialize_student(user, detailed: true) }
    end

    private

    def student_user
      User.student.includes(student_profile: { student_enrollments: %i[grade academic_year] }).find(params[:id])
    end

    def student_params
      params.require(:student).permit(:status)
    end

    def serialize_student(user, detailed: false)
      profile = user.student_profile
      enrollment = profile.student_enrollments.active.max_by(&:enrolled_at)
      payload = {
        id: user.id,
        name: user.name,
        phone: user.phone_e164,
        email: user.email,
        status: user.status,
        governorate: profile.governorate,
        school: profile.school,
        grade: enrollment&.grade&.name,
        grade_id: enrollment&.grade_id,
        grade_level: enrollment&.grade&.level,
        academic_year: enrollment&.academic_year&.name,
        academic_year_id: enrollment&.academic_year_id,
        created_at: user.created_at,
        last_active_at: user.user_sessions.maximum(:last_seen_at)
      }
      return payload unless detailed

      payload.merge(
        birth_date: profile.birth_date,
        parent_phone: profile.parent_phone_e164,
        devices_count: profile.device_registrations.active.count
      )
    end
  end
end
