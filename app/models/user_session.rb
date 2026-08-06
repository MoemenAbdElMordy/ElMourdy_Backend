class UserSession < ApplicationRecord
  STALE_AFTER = 30.days

  enum :status, { active: 0, ended: 1, revoked: 2 }, validate: true

  belongs_to :user
  belongs_to :device_registration, optional: true

  validates :session_token_digest, presence: true, uniqueness: true, length: { is: 64 }
  validates :started_at, :last_seen_at, presence: true
  validate :student_session_has_device

  scope :live, -> { active.order(last_seen_at: :desc) }
  scope :stale, ->(at = Time.current) { active.where(last_seen_at: ...STALE_AFTER.ago(at)) }

  def stale?(at = Time.current)
    last_seen_at < STALE_AFTER.ago(at)
  end

  private

  def student_session_has_device
    errors.add(:device_registration, "is required for student sessions") if user&.student? && device_registration.blank?
  end
end
