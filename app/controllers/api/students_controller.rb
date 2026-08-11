module Api
  class StudentsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_students") },
      except: %i[update_parent_phone destroy_device]
    before_action -> { require_teacher_or_assistant_permission!("manage_parent_phone") },
      only: :update_parent_phone
    before_action -> { require_teacher_or_assistant_permission!("manage_devices") },
      only: :destroy_device

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
      audit!(action: "student.status_updated", target: user, metadata: { status: user.status })
      render json: { student: serialize_student(user, detailed: true) }
    end

    def update_enrollment
      user = student_user
      profile = user.student_profile
      year = AcademicYear.find(enrollment_params.fetch(:academic_year_id))
      grade = Grade.enabled.find(enrollment_params.fetch(:grade_id))

      StudentEnrollment.transaction do
        profile.student_enrollments.active.where.not(academic_year: year).update_all(
          status: StudentEnrollment.statuses[:transferred], updated_at: Time.current
        )
        enrollment = profile.student_enrollments.find_or_initialize_by(academic_year: year)
        enrollment.update!(grade:, status: :active, enrolled_at: Time.current)
      end
      audit!(action: "student.enrollment_updated", target: user,
        metadata: { academic_year_id: year.id, grade_id: grade.id })
      render json: { student: serialize_student(student_user, detailed: true) }
    end

    def reset_password
      user = student_user
      password = password_params.fetch(:password)
      user.update!(password:, password_confirmation: password)
      user.user_sessions.active.update_all(status: UserSession.statuses[:revoked], ended_at: Time.current)
      audit!(action: "student.password_reset", target: user)
      head :no_content
    end

    def update_parent_phone
      user = student_user
      profile = user.student_profile
      new_phone = PhoneNumbers::Normalize.call(parent_phone_params.fetch(:phone))
      if new_phone == user.phone_e164
        return render json: {
          error: { code: "invalid_parent_phone", message: "The parent phone must differ from the student phone" }
        }, status: :unprocessable_entity
      end

      StudentProfile.transaction do
        profile.update!(parent_phone_e164: new_phone)
        profile.student_parent_links.active.joins(:parent_profile)
          .where.not(parent_profiles: { verified_parent_phone_e164: new_phone })
          .update_all(status: StudentParentLink.statuses[:removed], updated_at: Time.current)
        ParentProfile.where(verified_parent_phone_e164: new_phone).find_each do |parent_profile|
          link = profile.student_parent_links.find_or_initialize_by(parent_profile:)
          link.update!(status: :active, relation: link.relation || :other, linked_at: Time.current)
        end
      end

      audit!(action: "student.parent_phone_updated", target: user, metadata: { parent_phone: new_phone })
      render json: { student: serialize_student(student_user, detailed: true) }
    end

    def destroy_device
      user = student_user
      device = user.student_profile.device_registrations.active.find(params[:device_id])
      device.transaction do
        device.user_sessions.active.update_all(
          status: UserSession.statuses[:revoked], ended_at: Time.current, updated_at: Time.current
        )
        device.update!(status: :removed, removed_at: Time.current)
      end
      audit!(action: "student.device_removed", target: user, metadata: { device_registration_id: device.id })
      head :no_content
    end

    private

    def student_user
      User.student.includes(student_profile: { student_enrollments: %i[grade academic_year] }).find(params[:id])
    end

    def student_params
      params.require(:student).permit(:status)
    end

    def enrollment_params
      params.require(:enrollment).permit(:academic_year_id, :grade_id)
    end

    def password_params
      params.require(:student).permit(:password)
    end

    def parent_phone_params
      params.require(:parent_phone).permit(:phone)
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
        devices_count: profile.device_registrations.active.count,
        devices: profile.device_registrations.recent.map do |device|
          {
            id: device.id, name: device.device_name, browser: device.browser, os: device.os,
            status: device.status, last_seen_at: device.last_seen_at
          }
        end,
        attempts: profile.exam_attempts.includes(:exam).recent.limit(20).map do |attempt|
          {
            id: attempt.id, exam_title: attempt.exam.title, status: attempt.status,
            percent: attempt.percent, result_status: attempt.result_status, submitted_at: attempt.submitted_at
          }
        end,
        progress: {
          completed_lectures: profile.lecture_watch_events.where.not(completed_at: nil).distinct.count(:lecture_id),
          watched_lectures: profile.lecture_watch_events.distinct.count(:lecture_id),
          highest_score: profile.exam_attempts.submitted.maximum(:percent)&.to_f
        }
      )
    end
  end
end
