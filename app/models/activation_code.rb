class ActivationCode < ApplicationRecord
  enum :status, { unused: 0, redeemed: 1, disabled: 2, deleted: 3 }, validate: true

  belongs_to :activation_code_batch
  belongs_to :redeemed_by_student_profile, class_name: "StudentProfile", optional: true
  has_one :lesson_access_grant, dependent: :restrict_with_error

  validates :code_digest, presence: true, uniqueness: true, length: { is: 64 }
  validate :redemption_state_is_consistent

  scope :redeemable, -> { unused.where(deleted_at: nil) }

  private

  def redemption_state_is_consistent
    has_redemption = redeemed_by_student_profile_id.present? && redeemed_at.present?
    return if redeemed? ? has_redemption : !has_redemption

    errors.add(:status, "does not match the redemption data")
  end
end
