class VideoVariant < ApplicationRecord
  enum :status, { processing: 0, ready: 1, failed: 2 }, validate: true

  belongs_to :video_asset

  validates :quality, presence: true, inclusion: { in: %w[360p 480p 720p] },
    uniqueness: { scope: :video_asset_id }
  validates :file_key, presence: true
  validates :size_bytes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
