module Api
  class ChaptersController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_content") }

    def create
      chapter = Chapter.create!(chapter_params.merge(position: chapter_params[:position].presence || next_position))
      render json: { chapter: serialize(chapter) }, status: :created
    end

    def update
      chapter.update!(chapter_params)
      render json: { chapter: serialize(chapter) }
    end

    def destroy
      chapter.destroy!
      head :no_content
    end

    def reorder
      Curriculum::Reorder.call(scope: Chapter.where(branch_id: params.require(:branch_id)), ordered_ids: params.require(:ordered_ids))
      head :no_content
    end

    private

    def chapter = @chapter ||= Chapter.find(params[:id])
    def chapter_params = params.require(:chapter).permit(:branch_id, :title, :position, :status)
    def next_position = Chapter.where(branch_id: chapter_params[:branch_id]).maximum(:position).to_i + 1
    def serialize(record) = record.as_json(only: %i[id branch_id title position status])
  end
end
