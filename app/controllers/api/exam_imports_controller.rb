module Api
  class ExamImportsController < ApplicationController
    before_action :authenticate_user!

    def create
      permission = params[:assessment_type].to_s == "homework" ? "manage_homeworks" : "manage_exams"
      require_teacher_or_assistant_permission!(permission)
      return if performed?

      result = Documents::ExamDocxParser.new(params[:file]).call
      render json: { import: result }
    end
  end
end
