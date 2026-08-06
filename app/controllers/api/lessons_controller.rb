module Api
  class LessonsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_content") }

    def create
      lesson = Lesson.create!(lesson_params.merge(position: lesson_params[:position].presence || next_position))
      render json: { lesson: serialize(lesson) }, status: :created
    end

    def update
      lesson.update!(lesson_params)
      render json: { lesson: serialize(lesson) }
    end

    def destroy
      lesson.destroy!
      head :no_content
    end

    def reorder
      Curriculum::Reorder.call(scope: Lesson.where(chapter_id: params.require(:chapter_id)), ordered_ids: params.require(:ordered_ids))
      head :no_content
    end

    private

    def lesson = @lesson ||= Lesson.find(params[:id])
    def lesson_params = params.require(:lesson).permit(:chapter_id, :title, :position, :status, :publish_at, :is_free)
    def next_position = Lesson.where(chapter_id: lesson_params[:chapter_id]).maximum(:position).to_i + 1
    def serialize(record) = record.as_json(only: %i[id chapter_id title position status publish_at is_free])
  end
end
