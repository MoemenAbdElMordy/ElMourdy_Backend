module Api
  class CurriculumLocationsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_content") }

    def index
      lessons = Lesson.includes(chapter: { branch: %i[academic_year grade] })
        .joins(chapter: { branch: %i[academic_year grade] })
        .merge(AcademicYear.chronological)
        .order("academic_years.starts_on DESC", "grades.level ASC", "branches.position ASC", "chapters.position ASC", "lessons.position ASC")

      render json: { locations: lessons.map { |lesson| serialize(lesson) } }
    end

    private

    def serialize(lesson)
      branch = lesson.chapter.branch
      {
        lesson_id: lesson.id,
        academic_year: branch.academic_year.name,
        grade: branch.grade.name,
        grade_level: branch.grade.level,
        branch: branch.title,
        chapter: lesson.chapter.title,
        lesson: lesson.title
      }
    end
  end
end
