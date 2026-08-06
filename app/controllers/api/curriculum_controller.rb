module Api
  class CurriculumController < ApplicationController
    before_action :authenticate_user!

    def show
      if current_user.student?
        render json: { curriculum: student_curriculum }
      else
        require_teacher_or_assistant_permission!("manage_content")
        return if performed?

        render json: { curriculum: managed_curriculum }
      end
    end

    private

    def managed_curriculum
      year = params[:academic_year_id].present? ? AcademicYear.find(params[:academic_year_id]) : AcademicYear.active.first
      grade = params[:grade_id].present? ? Grade.find(params[:grade_id]) : Grade.enabled.first
      serialize_tree(year:, grade:, visible_only: false)
    end

    def student_curriculum
      enrollment = current_user.student_profile.student_enrollments.active.includes(:academic_year, :grade).order(enrolled_at: :desc).first
      return empty_tree unless enrollment

      serialize_tree(year: enrollment.academic_year, grade: enrollment.grade, visible_only: true)
    end

    def serialize_tree(year:, grade:, visible_only:)
      return empty_tree unless year && grade

      branches = Branch.where(academic_year: year, grade: grade).ordered
      branches = branches.visible if visible_only
      {
        academic_year: { id: year.id, name: year.name },
        grade: { id: grade.id, name: grade.name, level: grade.level },
        branches: branches.map { |branch| serialize_branch(branch, visible_only:) }
      }
    end

    def serialize_branch(branch, visible_only:)
      chapters = branch.chapters.ordered
      chapters = chapters.visible if visible_only
      content_payload(branch).merge(chapters: chapters.map { |chapter| serialize_chapter(chapter, visible_only:) })
    end

    def serialize_chapter(chapter, visible_only:)
      lessons = chapter.lessons.ordered
      lessons = lessons.visible if visible_only
      content_payload(chapter).merge(lessons: lessons.map { |lesson| serialize_lesson(lesson, visible_only:) })
    end

    def serialize_lesson(lesson, visible_only:)
      lectures = lesson.lectures.ordered
      lectures = lectures.visible if visible_only
      content_payload(lesson).merge(
        is_free: lesson.is_free,
        lectures: lectures.map { |lecture| content_payload(lecture).merge(is_free: lecture.is_free, duration_seconds: lecture.duration_seconds) }
      )
    end

    def content_payload(record)
      { id: record.id, title: record.title, position: record.position, status: record.status, publish_at: record.try(:publish_at) }
    end

    def empty_tree
      { academic_year: nil, grade: nil, branches: [] }
    end
  end
end
