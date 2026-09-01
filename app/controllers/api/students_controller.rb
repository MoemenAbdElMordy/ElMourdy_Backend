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
      users = users.where("users.name LIKE :query OR users.phone_e164 LIKE :query OR users.email LIKE :query", query: "%#{params[:query]}%") if params[:query].present?
      users = users.joins(student_profile: :student_enrollments).where(student_enrollments: { grade_id: params[:grade_id] }).distinct if params[:grade_id].present?

      users, pagination = paginate(users.order(created_at: :desc))
      render json: { students: users.map { |user| serialize_student(user) }, pagination: }
    end

    def show
      user = student_user
      render json: { student: serialize_student(user, detailed: true) }
    end

    def export
      users = filtered_students.includes(student_profile: { student_enrollments: %i[grade academic_year] }).order(created_at: :desc)
      document = Documents::ReportDocuments.students(users)
      send_data document, filename: "students-#{Date.current}.docx", type: Documents::DocxBuilder::CONTENT_TYPE
    end

    def export_one
      user = student_user
      document = Documents::ReportDocuments.student(user)
      send_data document, filename: "student-#{user.id}-report.docx", type: Documents::DocxBuilder::CONTENT_TYPE
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

    def filtered_students
      users = User.student
      users = users.where(status: params[:status]) if User.statuses.key?(params[:status])
      users = users.where("users.name LIKE :query OR users.phone_e164 LIKE :query OR users.email LIKE :query", query: "%#{params[:query]}%") if params[:query].present?
      users = users.joins(student_profile: :student_enrollments).where(student_enrollments: { grade_id: params[:grade_id] }).distinct if params[:grade_id].present?
      users
    end

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
        center_name: profile.center_name,
        grade: enrollment&.grade&.name,
        grade_id: enrollment&.grade_id,
        grade_level: enrollment&.grade&.level,
        academic_year: enrollment&.academic_year&.name,
        academic_year_id: enrollment&.academic_year_id,
        created_at: user.created_at,
        last_active_at: user.user_sessions.maximum(:last_seen_at),
        account_verified: user.phone_verified_at.present?,
        verified_at: user.phone_verified_at
      }
      return payload unless detailed

      payload.merge(
        birth_date: profile.birth_date,
        parent_phone: profile.parent_phone_e164,
        devices_count: profile.device_registrations.active.count,
        active_sessions_count: user.user_sessions.active.count,
        total_sessions_count: user.user_sessions.count,
        last_login_at: user.user_sessions.maximum(:started_at),
        devices: profile.device_registrations.recent.map do |device|
          {
            id: device.id, name: device.device_name, browser: device.browser, os: device.os,
            status: device.status, last_seen_at: device.last_seen_at
          }
        end,
        attempts: profile.exam_attempts.includes(:exam).recent.limit(100).map do |attempt|
          {
            id: attempt.id, exam_id: attempt.exam_id, exam_title: attempt.exam.title,
            assessment_type: attempt.exam.assessment_type, attempt_number: attempt.attempt_number,
            status: attempt.status, score_points: attempt.score_points, max_points: attempt.max_points,
            percent: attempt.percent, result_status: attempt.result_status, started_at: attempt.started_at,
            submitted_at: attempt.submitted_at
          }
        end,
        progress: {
          completed_lectures: profile.lecture_watch_events.where.not(completed_at: nil).distinct.count(:lecture_id),
          watched_lectures: profile.lecture_watch_events.distinct.count(:lecture_id),
          highest_score: profile.exam_attempts.submitted.maximum(:percent)&.to_f
        },
        video_progress: video_progress(profile, enrollment),
        assessments: assessment_progress(profile, enrollment)
      )
    end

    def assessment_progress(profile, enrollment)
      return [] unless enrollment

      direct_ids = Exam.where(academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id).select(:id)
      assigned_ids = ExamGradeAssignment.where(grade_id: enrollment.grade_id).select(:exam_id)
      exams = Exam.published.where(academic_year_id: enrollment.academic_year_id)
        .where(id: direct_ids).or(
          Exam.published.where(academic_year_id: enrollment.academic_year_id, id: assigned_ids)
        ).includes(:exam_questions, :branch, lesson: { chapter: :branch }, chapter: :branch).order(created_at: :desc)
      attempts = profile.exam_attempts.where(exam_id: exams.map(&:id)).group_by(&:exam_id)

      exams.map do |exam|
        exam_attempts = attempts.fetch(exam.id, [])
        submitted = exam_attempts.select(&:submitted?)
        latest = exam_attempts.max_by(&:started_at)
        {
          id: exam.id,
          title: exam.title,
          assessment_type: exam.assessment_type,
          status: if submitted.any? then "submitted" elsif exam_attempts.any? then "in_progress" else "not_started" end,
          scope: assessment_scope(exam),
          questions_count: exam.exam_questions.size,
          max_attempts: exam.max_attempts,
          attempts_count: exam_attempts.size,
          submitted_attempts_count: submitted.size,
          best_percent: submitted.filter_map { |attempt| attempt.percent&.to_f }.max,
          latest_percent: latest&.percent&.to_f,
          latest_result_status: latest&.result_status,
          first_started_at: exam_attempts.map(&:started_at).compact.min,
          last_activity_at: exam_attempts.map { |attempt| attempt.submitted_at || attempt.updated_at }.compact.max
        }
      end
    end

    def assessment_scope(exam)
      return "Comprehensive" if exam.scope_comprehensive?
      return [ exam.lesson.chapter.branch.title, exam.lesson.chapter.title, exam.lesson.title ].join(" - ") if exam.lesson
      return [ exam.chapter.branch.title, exam.chapter.title ].join(" - ") if exam.chapter

      exam.branch.title
    end

    def video_progress(profile, enrollment)
      return [] unless enrollment

      lesson_ids = Lesson.joins(chapter: :branch).where(
        branches: { academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id }
      ).select(:id)
      lecture_ids = Lecture.where(lesson_id: lesson_ids)
        .or(Lecture.where(id: LecturePlacement.where(lesson_id: lesson_ids).select(:lecture_id))).select(:id)
      lectures = Lecture.published
        .where("lectures.publish_at IS NULL OR lectures.publish_at <= ?", Time.current)
        .where(id: lecture_ids)
        .includes(:selected_video_asset, :video_assets, lesson: { chapter: :branch }).distinct.order(:position)
        .select { |lecture| lecture.video_source_type_youtube? || lecture.effective_video_asset.present? }

      events = profile.lecture_watch_events.where(lecture_id: lectures.map(&:id))
      watched_seconds = events.group(:lecture_id).sum(:watched_seconds)
      last_positions = events.group(:lecture_id).maximum(:last_position_seconds)
      last_watched = events.group(:lecture_id).maximum(:updated_at)
      completed_ids = events.where.not(completed_at: nil).distinct.pluck(:lecture_id).to_set

      lectures.map do |lecture|
        duration = lecture.duration_seconds.to_i.nonzero? || (lecture.effective_video_asset&.duration_seconds).to_i
        watched = watched_seconds.fetch(lecture.id, 0)
        completed = completed_ids.include?(lecture.id)
        percent = completed ? 100 : (duration.positive? ? [ (watched.to_f / duration * 100).round, 100 ].min : 0)
        {
          lecture_id: lecture.id,
          title: lecture.title,
          lesson: lecture.lesson.title,
          chapter: lecture.lesson.chapter.title,
          branch: lecture.lesson.chapter.branch.title,
          duration_seconds: duration,
          watched_seconds: watched,
          last_position_seconds: last_positions.fetch(lecture.id, 0),
          progress_percent: percent,
          watched: watched.positive? || completed,
          completed:,
          last_watched_at: last_watched[lecture.id]
        }
      end
    end
  end
end
