class LecturePlacement < ApplicationRecord
  include CatalogCacheable

  belongs_to :lecture
  belongs_to :lesson

  validates :lesson_id, uniqueness: { scope: :lecture_id }
  validate :lesson_is_not_primary

  private

  def lesson_is_not_primary
    return unless lecture&.lesson_id == lesson_id

    errors.add(:lesson, "is already the lecture's primary location")
  end
end
