class Lecture < ApplicationRecord
  include CatalogCacheable
  include Publishable

  belongs_to :lesson
  has_many :lecture_placements, dependent: :destroy
  has_many :additional_lessons, through: :lecture_placements, source: :lesson
  has_many :video_assets, dependent: :restrict_with_error
  has_many :lecture_watch_events, dependent: :restrict_with_error

  validates :title, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :lesson_id }
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def all_lessons
    Lesson.where(id: [ lesson_id, *additional_lesson_ids ])
  end
end
