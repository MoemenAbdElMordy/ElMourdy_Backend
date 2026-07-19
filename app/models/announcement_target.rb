class AnnouncementTarget < ApplicationRecord
  enum :target_type, { grade: 0, user: 1 }, prefix: :target, validate: true

  belongs_to :announcement
  belongs_to :grade, optional: true
  belongs_to :user, optional: true

  validate :target_reference_matches_type

  private

  def target_reference_matches_type
    valid = target_grade? ? grade_id.present? && user_id.nil? : user_id.present? && grade_id.nil?
    errors.add(:target_type, "does not match the supplied target") unless valid
  end
end
