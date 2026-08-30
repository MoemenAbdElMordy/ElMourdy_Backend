class LectureAccessGrant < ApplicationRecord
  enum :status, { active: 0, expired: 1, revoked: 2 }, validate: true

  belongs_to :student_profile
  belongs_to :lecture
  belongs_to :academic_year
  belongs_to :activation_code

  validates :student_profile_id, uniqueness: { scope: %i[lecture_id academic_year_id] }
  validates :activation_code_id, uniqueness: true
  validates :expires_on, presence: true

  scope :currently_active, -> { active.where("expires_on >= ?", Date.current) }
end
