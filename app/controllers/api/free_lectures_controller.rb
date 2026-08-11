module Api
  class FreeLecturesController < ApplicationController
    def index
      render json: { lectures: playable_free_lectures.filter_map { |lecture| serialize(lecture) } }
    end

    private

    def playable_free_lectures
      visible_branch_ids = Branch.visible.select(:id)
      visible_chapter_ids = Chapter.visible.where(branch_id: visible_branch_ids).select(:id)
      visible_lesson_ids = Lesson.visible.where(chapter_id: visible_chapter_ids).select(:id)

      Lecture.published
        .where("lectures.publish_at IS NULL OR lectures.publish_at <= ?", Time.current)
        .joins(:lesson)
        .where(lesson_id: visible_lesson_ids)
        .where("lectures.is_free = ? OR lessons.is_free = ?", true, true)
        .includes(lesson: { chapter: { branch: :grade } }, video_assets: :video_variants)
        .order("lectures.position")
    end

    def serialize(lecture)
      asset = lecture.video_assets.find do |candidate|
        candidate.ready? && candidate.video_variants.any?(&:ready?)
      end
      return unless asset

      branch = lecture.lesson.chapter.branch
      {
        id: lecture.id,
        title: lecture.title,
        duration_seconds: lecture.duration_seconds || asset.duration_seconds,
        available_qualities: asset.video_variants.select(&:ready?).map(&:quality),
        branch: { id: branch.id, title: branch.title },
        grade: { id: branch.grade.id, name: branch.grade.name }
      }
    end
  end
end
