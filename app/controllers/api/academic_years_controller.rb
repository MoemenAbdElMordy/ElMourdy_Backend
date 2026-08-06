module Api
  class AcademicYearsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_academic_years") }

    def index
      render json: {
        academic_years: AcademicYear.chronological.map { |year| serialize_year(year) },
        grades: Grade.enabled.map { |grade| { id: grade.id, name: grade.name, level: grade.level } }
      }
    end

    def create
      year = AcademicYear.transaction do
        AcademicYear.active.update_all(status: AcademicYear.statuses[:archived]) if year_params[:status] == "active"
        AcademicYear.create!(year_params)
      end
      render json: { academic_year: serialize_year(year) }, status: :created
    end

    def update
      year = AcademicYear.find(params[:id])
      AcademicYear.transaction do
        AcademicYear.active.where.not(id: year.id).update_all(status: AcademicYear.statuses[:archived]) if year_params[:status] == "active"
        year.update!(year_params)
      end
      render json: { academic_year: serialize_year(year) }
    end

    private

    def year_params
      params.require(:academic_year).permit(:name, :starts_on, :ends_on, :status)
    end

    def serialize_year(year)
      {
        id: year.id,
        name: year.name,
        starts_on: year.starts_on,
        ends_on: year.ends_on,
        status: year.status,
        students_count: year.student_enrollments.active.count
      }
    end
  end
end
