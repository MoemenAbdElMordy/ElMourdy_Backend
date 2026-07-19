class Lecture < ApplicationRecord
  include Publishable

  belongs_to :lesson
  has_many :video_assets, dependent: :restrict_with_error
  has_many :lecture_watch_events, dependent: :restrict_with_error

  validates :title, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :lesson_id }
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
