module Api
  class ManagementReportsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("view_reports") }

    def show
      enrollments = StudentEnrollment.active.includes(:grade, :academic_year, student_profile: :user)
      enrollments = enrollments.where(academic_year_id: params[:academic_year_id]) if params[:academic_year_id].present?
      enrollments = enrollments.where(grade_id: params[:grade_id]) if params[:grade_id].present?
      profile_ids = enrollments.pluck(:student_profile_id)
      attempts = ExamAttempt.submitted.where(student_profile_id: profile_ids)
      watch_events = LectureWatchEvent.where(student_profile_id: profile_ids)
      scores = attempts.group(:student_profile_id).average(:percent)
      completed = watch_events.where.not(completed_at: nil).group(:student_profile_id).distinct.count(:lecture_id)

      students = enrollments.map do |enrollment|
        profile = enrollment.student_profile
        {
          id: profile.user_id, name: profile.user.name, grade: enrollment.grade.name,
          academic_year: enrollment.academic_year.name,
          average_score: scores[profile.id]&.to_f,
          completed_lectures: completed.fetch(profile.id, 0),
          attempts_count: attempts.where(student_profile_id: profile.id).count,
          last_active_at: profile.user.user_sessions.maximum(:last_seen_at)
        }
      end

      render json: { report: {
        overview: {
          students_count: students.size, attempts_count: attempts.count,
          average_score: attempts.average(:percent)&.to_f,
          passed_count: attempts.passed.count, risk_count: attempts.risk.count,
          failed_count: attempts.failed.count,
          completed_lecture_events: watch_events.where.not(completed_at: nil).count
        },
        students:
      } }
    end
  end
end
