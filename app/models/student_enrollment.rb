class StudentEnrollment < ApplicationRecord
  enum :status, { active: 0, archived: 1, transferred: 2 }, validate: true

  belongs_to :student_profile
  belongs_to :academic_year
  belongs_to :grade

  validates :enrolled_at, presence: true
  validates :student_profile_id, uniqueness: { scope: :academic_year_id }

  scope :current, -> { active.includes(:grade, :academic_year) }
end
