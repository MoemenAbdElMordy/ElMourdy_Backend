module Api
  class ManagementReportsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("view_reports") }

    def show
      report, pagination = build_report(filtered_enrollments, paginate_records: true)
      render json: { report:, pagination: }
    end

    def export
      report, = build_report(filtered_enrollments, paginate_records: false)
      document = Documents::ReportDocuments.management(
        overview: report[:overview], students: report[:students],
        filters: { academic_year_id: params[:academic_year_id], grade_id: params[:grade_id] }
      )
      send_data document, filename: "management-report-#{Date.current}.docx", type: Documents::DocxBuilder::CONTENT_TYPE
    end

    private

    def filtered_enrollments
      enrollments = StudentEnrollment.active.includes(:grade, :academic_year, student_profile: :user)
      enrollments = enrollments.where(academic_year_id: params[:academic_year_id]) if params[:academic_year_id].present?
      enrollments = enrollments.where(grade_id: params[:grade_id]) if params[:grade_id].present?
      enrollments
    end

    def build_report(enrollments, paginate_records:)
      profile_ids = enrollments.distinct.pluck(:student_profile_id)
      attempts = ExamAttempt.submitted.where(student_profile_id: profile_ids)
      watch_events = LectureWatchEvent.where(student_profile_id: profile_ids)
      scores = attempts.group(:student_profile_id).average(:percent)
      completed = watch_events.where.not(completed_at: nil).group(:student_profile_id).distinct.count(:lecture_id)
      attempt_counts = attempts.group(:student_profile_id).count
      overview = {
        students_count: enrollments.distinct.count(:student_profile_id), attempts_count: attempts.count,
        average_score: attempts.average(:percent)&.to_f,
        passed_count: attempts.passed.count, risk_count: attempts.risk.count,
        failed_count: attempts.failed.count,
        completed_lecture_events: watch_events.where.not(completed_at: nil).count
      }
      if paginate_records
        enrollments, pagination = paginate(enrollments.order(enrolled_at: :desc))
      else
        enrollments = enrollments.order(enrolled_at: :desc)
        pagination = nil
      end
      user_ids = enrollments.map { |enrollment| enrollment.student_profile.user_id }
      last_active = UserSession.where(user_id: user_ids).group(:user_id).maximum(:last_seen_at)

      students = enrollments.map do |enrollment|
        profile = enrollment.student_profile
        {
          id: profile.user_id, name: profile.user.name, grade: enrollment.grade.name,
          academic_year: enrollment.academic_year.name,
          average_score: scores[profile.id]&.to_f,
          completed_lectures: completed.fetch(profile.id, 0),
          attempts_count: attempt_counts.fetch(profile.id, 0),
          last_active_at: last_active[profile.user_id]
        }
      end

      [ { overview:, students: }, pagination ]
    end
  end
end
