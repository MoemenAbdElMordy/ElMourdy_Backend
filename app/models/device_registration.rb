class DeviceRegistration < ApplicationRecord
  enum :status, { active: 0, removed: 1, blocked: 2 }, validate: true

  belongs_to :student_profile
  has_many :user_sessions, dependent: :restrict_with_error
  has_many :lecture_watch_events, dependent: :restrict_with_error

  validates :device_fingerprint_digest, presence: true, length: { is: 64 },
    uniqueness: { scope: :student_profile_id }
  validates :ip_address, length: { maximum: 45 }, allow_blank: true

  scope :recent, -> { order(last_seen_at: :desc) }
end
