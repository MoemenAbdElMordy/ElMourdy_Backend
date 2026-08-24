class VideoAsset < ApplicationRecord
  include CatalogCacheable
  enum :processing_status, { uploaded: 0, processing: 1, ready: 2, failed: 3 }, validate: true

  belongs_to :lecture
  belongs_to :created_by_user, class_name: "User", optional: true
  has_many :video_variants, dependent: :destroy
  has_many :selected_by_lectures, class_name: "Lecture", foreign_key: :selected_video_asset_id,
    inverse_of: :selected_video_asset, dependent: :restrict_with_error

  validates :original_file_key, presence: true
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
