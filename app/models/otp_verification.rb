class OtpVerification < ApplicationRecord
  include E164Phone

  enum :purpose, {
    student_registration: 0, parent_registration: 1, parent_phone_change: 2
  }, validate: true
  enum :status, { pending: 0, verified: 1, expired: 2, failed: 3 }, validate: true

  belongs_to :user, optional: true
  has_many :parent_phone_changes, dependent: :restrict_with_error

  validates :phone_e164, :code_digest, :expires_at, presence: true
  validates :code_digest, length: { is: 64 }
  validates :attempts_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates_e164_phone :phone_e164
  validate :expiration_follows_creation

  scope :usable, -> { pending.where("expires_at > ?", Time.current) }

  private

  def expiration_follows_creation
    return if created_at.blank? || expires_at.blank? || expires_at > created_at

    errors.add(:expires_at, "must be after creation")
  end
end
