module Api
  class BranchesController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_content") }

    def create
      branch = Branch.create!(branch_params.merge(position: branch_params[:position].presence || next_position))
      render json: { branch: serialize(branch) }, status: :created
    end

    def update
      branch.update!(branch_params)
      render json: { branch: serialize(branch) }
    end

    def destroy
      branch.destroy!
      head :no_content
    end

    def reorder
      Curriculum::Reorder.call(scope: Branch.where(academic_year_id: params.require(:academic_year_id), grade_id: params.require(:grade_id)), ordered_ids: params.require(:ordered_ids))
      head :no_content
    end

    private

    def branch = @branch ||= Branch.find(params[:id])
    def branch_params = params.require(:branch).permit(:academic_year_id, :grade_id, :title, :position, :status)
    def next_position = Branch.where(academic_year_id: branch_params[:academic_year_id], grade_id: branch_params[:grade_id]).maximum(:position).to_i + 1
    def serialize(record) = record.as_json(only: %i[id academic_year_id grade_id title position status])
  end
end
