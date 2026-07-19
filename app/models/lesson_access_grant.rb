class LessonAccessGrant < ApplicationRecord
  enum :source, { code: 0, free: 1, manual: 2 }, validate: true
  enum :status, { active: 0, expired: 1, revoked: 2 }, validate: true

  belongs_to :student_profile
  belongs_to :lesson
  belongs_to :academic_year
  belongs_to :activation_code, optional: true

  validates :student_profile_id, uniqueness: { scope: %i[lesson_id academic_year_id] }
  validates :expires_on, presence: true
  validate :activation_code_matches_source

  scope :currently_active, -> { active.where("expires_on >= ?", Date.current) }

  private

  def activation_code_matches_source
    return if code? ? activation_code_id.present? : activation_code_id.nil?

    errors.add(:activation_code, "must be present only for code-based access")
  end
end
