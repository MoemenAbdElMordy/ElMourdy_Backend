module Api
  class GradesController < ApplicationController
    def index
      version = CacheVersions.current("catalog")
      grades = Rails.cache.fetch("catalog/#{version}/grades", expires_in: 1.hour) do
        Grade.enabled.map { |grade| serialize_grade(grade) }
      end
      render json: { grades: }
    end

    private

    def serialize_grade(grade)
      { id: grade.id, name: grade.name, level: grade.level }
    end
  end
end
