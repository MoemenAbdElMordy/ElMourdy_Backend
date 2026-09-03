module Api
  class FreeLecturesController < ApplicationController
    def index
      version = CacheVersions.current("catalog")
      lectures = Rails.cache.fetch("catalog/#{version}/free-lectures", expires_in: 5.minutes) do
        playable_free_lectures.filter_map { |lecture| serialize(lecture) }
      end
      render json: { lectures: }
    end

    def thumbnail
      lecture = playable_free_lectures.find(params[:id])
      return render_not_found if lecture.thumbnail_key.blank?
      return unless stale?(etag: lecture.thumbnail_key, last_modified: lecture.updated_at, public: true)

      expires_in 1.day, public: true
      send_data storage.read(lecture.thumbnail_key), type: thumbnail_content_type(lecture),
        disposition: "inline", filename: File.basename(lecture.thumbnail_key)
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
        description: lecture.description,
        duration_seconds: lecture.duration_seconds || asset.duration_seconds,
        available_qualities: asset.video_variants.select(&:ready?).map(&:quality),
        has_thumbnail: lecture.thumbnail_key.present?,
        branch: { id: branch.id, title: branch.title },
        grade: { id: branch.grade.id, name: branch.grade.name, level: branch.grade.level }
      }
    end

    def storage = @storage ||= Videos::Storage.build

    def thumbnail_content_type(lecture)
      Rack::Mime.mime_type(File.extname(lecture.thumbnail_key), "image/jpeg")
    end
  end
end
