module Api
  class LecturesController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_content") }

    def create
      lecture = Lecture.transaction do
        record = Lecture.create!(lecture_params.merge(position: lecture_params[:position].presence || next_position))
        sync_placements(record)
        record
      end
      render json: { lecture: serialize(lecture) }, status: :created
    end

    def update
      Lecture.transaction do
        lecture.update!(lecture_params)
        sync_placements(lecture)
      end
      render json: { lecture: serialize(lecture) }
    end

    def destroy
      lecture.destroy!
      head :no_content
    end

    def reorder
      Curriculum::Reorder.call(scope: Lecture.where(lesson_id: params.require(:lesson_id)), ordered_ids: params.require(:ordered_ids))
      head :no_content
    end

    private

    def lecture = @lecture ||= Lecture.find(params[:id])
    def lecture_params
      params.require(:lecture).permit(
        :lesson_id, :title, :description, :attachment_name, :attachment_url,
        :position, :status, :publish_at, :is_free, :duration_seconds
      )
    end
    def additional_lesson_ids
      return unless params.require(:lecture).key?(:additional_lesson_ids)

      Array(params.require(:lecture)[:additional_lesson_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    end
    def sync_placements(record)
      ids = additional_lesson_ids
      return if ids.nil?

      ids -= [ record.lesson_id ]
      lessons = Lesson.where(id: ids)
      raise ActiveRecord::RecordNotFound unless lessons.size == ids.size

      record.lecture_placements.where.not(lesson_id: ids).delete_all
      ids.each { |lesson_id| record.lecture_placements.find_or_create_by!(lesson_id:) }
    end
    def next_position = Lecture.where(lesson_id: lecture_params[:lesson_id]).maximum(:position).to_i + 1
    def serialize(record)
      record.as_json(
        only: %i[id lesson_id title description attachment_name attachment_url position status publish_at is_free duration_seconds]
      ).merge(
        has_thumbnail: record.thumbnail_key.present?,
        additional_lesson_ids: record.additional_lesson_ids
      )
    end
  end
end
