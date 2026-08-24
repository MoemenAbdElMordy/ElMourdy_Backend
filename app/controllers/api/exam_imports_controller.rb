module Api
  class ExamImportsController < ApplicationController
    before_action :authenticate_user!

    def create
      permission = params[:assessment_type].to_s == "homework" ? "manage_homeworks" : "manage_exams"
      require_teacher_or_assistant_permission!(permission)
      return if performed?

      parser = parser_for(params[:file])
      result = parser.new(params[:file]).call
      render json: { import: result }
    end

    private

    def parser_for(upload)
      extension = File.extname(upload&.original_filename.to_s).downcase
      return Documents::ExamDocxParser if extension == ".docx"
      return Documents::ExamPdfParser if extension == ".pdf"

      raise ApplicationService::Error, "Only DOCX and PDF files are supported"
    end
  end
end
