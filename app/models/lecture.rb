class Lecture < ApplicationRecord
  enum :video_source_type, { uploaded: 0, youtube: 1 }, prefix: true, validate: true

  belongs_to :selected_video_asset, class_name: "VideoAsset", optional: true
  include CatalogCacheable
  include Publishable

  belongs_to :lesson
  has_many :lecture_placements, dependent: :destroy
  has_many :additional_lessons, through: :lecture_placements, source: :lesson
  has_many :video_assets, dependent: :restrict_with_error

  validates :youtube_video_id, format: { with: /\A[A-Za-z0-9_-]{11}\z/ }, allow_nil: true
  validate :youtube_source_has_video_id

  def effective_video_asset
    selected_video_asset || video_assets.ready.order(created_at: :desc).first
  end

  has_many :lecture_watch_events, dependent: :restrict_with_error

  validates :title, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :lesson_id }
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def all_lessons
    Lesson.where(id: [ lesson_id, *additional_lesson_ids ])
  end

  private

  def youtube_source_has_video_id
    errors.add(:youtube_video_id, "is required for a YouTube source") if video_source_type_youtube? && youtube_video_id.blank?
  end
end
