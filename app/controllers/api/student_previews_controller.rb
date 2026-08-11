module Api
  class StudentPreviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_teacher!

    def show
      user = User.student.includes(student_profile: { student_enrollments: %i[academic_year grade] }).find(params[:id])
      profile = user.student_profile
      enrollment = profile.student_enrollments.active.order(enrolled_at: :desc).first
      return render json: { preview: empty_preview(user) } unless enrollment

      branches = Branch.where(academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id)
        .visible.includes(chapters: { lessons: :lectures }).ordered
      completed_ids = profile.lecture_watch_events.where.not(completed_at: nil).distinct.pluck(:lecture_id)
      subjects = branches.map do |branch|
        lectures = branch.chapters.select(&:published?).flat_map(&:lessons).select(&:published?)
          .flat_map(&:lectures).select(&:published?)
        {
          id: branch.id, title: branch.title, total_lectures: lectures.size,
          completed_lectures: (lectures.map(&:id) & completed_ids).size
        }
      end

      render json: { preview: {
        student: { id: user.id, name: user.name, status: user.status },
        enrollment: {
          academic_year: enrollment.academic_year.name,
          grade: enrollment.grade.name,
          grade_level: enrollment.grade.level
        },
        statistics: {
          total_lectures: subjects.sum { |subject| subject[:total_lectures] },
          completed_lectures: completed_ids.size,
          highest_score: profile.exam_attempts.submitted.maximum(:percent)&.to_f,
          subjects_count: subjects.size
        },
        subjects:
      } }
    end

    private

    def empty_preview(user)
      {
        student: { id: user.id, name: user.name, status: user.status }, enrollment: nil,
        statistics: { total_lectures: 0, completed_lectures: 0, highest_score: nil, subjects_count: 0 },
        subjects: []
      }
    end
  end
end
