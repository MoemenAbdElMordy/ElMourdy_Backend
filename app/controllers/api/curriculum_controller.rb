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
      return empty_tree unless year && grade

      version = CacheVersions.current("catalog")
      Rails.cache.fetch("catalog/#{version}/managed-curriculum/#{year.id}/#{grade.id}", expires_in: 10.minutes) do
        serialize_tree(year:, grade:, visible_only: false)
      end
    end

    def student_curriculum
      profile = current_user.student_profile
      enrollment = profile.student_enrollments.active.includes(:academic_year, :grade).order(enrolled_at: :desc).first
      return empty_tree unless enrollment

      @accessible_lesson_ids = profile.lesson_access_grants.currently_active
        .where(academic_year: enrollment.academic_year).pluck(:lesson_id)
      @watch_events_by_lecture = profile.lecture_watch_events.order(updated_at: :desc).each_with_object({}) do |event, events|
        events[event.lecture_id] ||= event
      end
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
        has_access: !visible_only || lesson.is_free || @accessible_lesson_ids.include?(lesson.id),
        lectures: lectures.map { |lecture| serialize_lecture(lecture) }
      )
    end

    def serialize_lecture(lecture)
      asset = lecture.video_assets.order(created_at: :desc).first
      watch_event = @watch_events_by_lecture&.fetch(lecture.id, nil)
      duration = lecture.duration_seconds.to_i.nonzero? || (asset&.duration_seconds).to_i
      content_payload(lecture).merge(
        is_free: lecture.is_free,
        description: lecture.description,
        attachment_name: lecture.attachment_name,
        attachment_url: lecture.attachment_url,
        has_thumbnail: lecture.thumbnail_key.present?,
        duration_seconds: duration,
        progress: watch_event && {
          last_position_seconds: watch_event.last_position_seconds,
          completed: watch_event.completed_at.present?
        },
        video_asset: asset&.as_json(only: %i[id processing_status duration_seconds available_qualities])
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
