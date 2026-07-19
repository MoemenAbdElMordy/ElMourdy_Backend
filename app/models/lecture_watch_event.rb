class LectureWatchEvent < ApplicationRecord
  belongs_to :student_profile
  belongs_to :lecture
  belongs_to :device_registration, optional: true

  validates :started_at, presence: true
  validates :last_position_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :ip_address, length: { maximum: 45 }, allow_blank: true
end
