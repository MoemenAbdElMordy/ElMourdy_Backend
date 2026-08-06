module Api
  class GradesController < ApplicationController
    def index
      render json: { grades: Grade.enabled.map { |grade| serialize_grade(grade) } }
    end

    private

    def serialize_grade(grade)
      { id: grade.id, name: grade.name, level: grade.level }
    end
  end
end
