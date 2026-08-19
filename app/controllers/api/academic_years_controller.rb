module Api
  class AcademicYearsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_academic_years") }

    def index
      render json: {
        academic_years: AcademicYear.chronological.map { |year| serialize_year(year) },
        grades: Grade.enabled.map { |grade| { id: grade.id, name: grade.name, level: grade.level } }
      }
    end

    def create
      year = AcademicYear.transaction do
        AcademicYear.active.update_all(status: AcademicYear.statuses[:archived]) if year_params[:status] == "active"
        AcademicYear.create!(year_params)
      end
      audit!(action: "academic_year.created", target: year)
      render json: { academic_year: serialize_year(year) }, status: :created
    end

    def update
      year = AcademicYear.find(params[:id])
      if year.active? && year_params[:status] == "archived" && AcademicYear.active.where.not(id: year.id).none?
        raise ApplicationService::Error, "Activate another academic year before archiving the current one"
      end
      AcademicYear.transaction do
        AcademicYear.active.where.not(id: year.id).update_all(status: AcademicYear.statuses[:archived]) if year_params[:status] == "active"
        year.update!(year_params)
      end
      audit!(action: "academic_year.updated", target: year, metadata: { status: year.status })
      render json: { academic_year: serialize_year(year) }
    end

    def copy_content
      target = AcademicYear.find(params[:id])
      source = AcademicYear.find(params.require(:source_year_id))
      raise ApplicationService::Error, "The target academic year already has curriculum content" if target.branches.exists?
      raise ApplicationService::Error, "An academic year cannot copy itself" if target == source

      copied_count = AcademicYear.transaction do
        source.branches.includes(chapters: { lessons: :lectures }).ordered.sum do |branch|
          copied_branch = target.branches.create!(
            grade: branch.grade, title: branch.title, position: branch.position, status: :draft
          )
          branch.chapters.ordered.each do |chapter|
            copied_chapter = copied_branch.chapters.create!(
              title: chapter.title, position: chapter.position, status: :draft
            )
            chapter.lessons.ordered.each do |lesson|
              copied_lesson = copied_chapter.lessons.create!(
                title: lesson.title, position: lesson.position, status: :draft,
                is_free: lesson.is_free, requires_exam_pass: false
              )
              lesson.lectures.ordered.each do |lecture|
                copied_lesson.lectures.create!(
                  title: lecture.title, position: lecture.position, status: :draft,
                  is_free: lecture.is_free, duration_seconds: lecture.duration_seconds
                )
              end
            end
          end
          1
        end
        target.update!(copied_from_year: source)
        source.branches.count
      end
      audit!(action: "academic_year.content_copied", target: target,
        metadata: { source_year_id: source.id, branches_count: copied_count })
      render json: { academic_year: serialize_year(target.reload), copied_branches_count: copied_count }
    end

    def rollover_students
      target = AcademicYear.find(params[:id])
      source = AcademicYear.find(params.require(:source_year_id))
      raise ApplicationService::Error, "An academic year cannot roll over into itself" if target == source

      moved = 0
      graduated = 0
      AcademicYear.transaction do
        source.student_enrollments.active.includes(:grade).find_each do |enrollment|
          next_grade = Grade.enabled.find_by(level: enrollment.grade.level + 1)
          if next_grade
            new_enrollment = target.student_enrollments.find_or_initialize_by(student_profile: enrollment.student_profile)
            new_enrollment.update!(grade: next_grade, status: :active, enrolled_at: Time.current)
            enrollment.update!(status: :transferred)
            moved += 1
          else
            enrollment.update!(status: :archived)
            graduated += 1
          end
        end
        AcademicYear.active.where.not(id: target.id).update_all(status: AcademicYear.statuses[:archived])
        target.update!(status: :active)
      end
      audit!(action: "academic_year.students_rolled_over", target: target,
        metadata: { source_year_id: source.id, moved_count: moved, graduated_count: graduated })
      render json: { academic_year: serialize_year(target.reload), moved_count: moved, graduated_count: graduated }
    end

    private

    def year_params
      params.require(:academic_year).permit(:name, :starts_on, :ends_on, :status)
    end

    def serialize_year(year)
      {
        id: year.id,
        name: year.name,
        starts_on: year.starts_on,
        ends_on: year.ends_on,
        status: year.status,
        students_count: year.student_enrollments.active.count,
        grades: Grade.enabled.order(:level).map { |grade| serialize_grade_summary(year, grade) }
      }
    end

    def serialize_grade_summary(year, grade)
      branches = year.branches.where(grade:)
      lessons = Lesson.joins(chapter: :branch).where(branches: { id: branches.select(:id) })
      lecture_ids = Lecture.where(lesson_id: lessons.select(:id)).select(:id)
      placed_lecture_ids = LecturePlacement.where(lesson_id: lessons.select(:id)).select(:lecture_id)
      {
        id: grade.id,
        name: grade.name,
        level: grade.level,
        students_count: year.student_enrollments.active.where(grade:).count,
        branches_count: branches.count,
        lessons_count: lessons.count,
        lectures_count: Lecture.where(id: lecture_ids).or(Lecture.where(id: placed_lecture_ids)).count
      }
    end
  end
end
