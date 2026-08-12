module Api
  class LecturesController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_content") }

    def create
      lecture = Lecture.create!(lecture_params.merge(position: lecture_params[:position].presence || next_position))
      render json: { lecture: serialize(lecture) }, status: :created
    end

    def update
      lecture.update!(lecture_params)
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
    def next_position = Lecture.where(lesson_id: lecture_params[:lesson_id]).maximum(:position).to_i + 1
    def serialize(record)
      record.as_json(
        only: %i[id lesson_id title description attachment_name attachment_url position status publish_at is_free duration_seconds]
      ).merge(has_thumbnail: record.thumbnail_key.present?)
    end
  end
end
