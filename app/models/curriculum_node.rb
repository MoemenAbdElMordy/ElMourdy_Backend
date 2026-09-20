# An additive presentation hierarchy. Legacy lessons remain the entitlement
# anchors: moving a node must never rewrite a lecture's lesson or grants.
class CurriculumNode < ApplicationRecord
  include CatalogCacheable

  belongs_to :branch
  belongs_to :parent, class_name: "CurriculumNode", optional: true
  belongs_to :lecture, optional: true
  belongs_to :legacy_chapter, class_name: "Chapter", optional: true
  belongs_to :legacy_lesson, class_name: "Lesson", optional: true
  has_many :children, class_name: "CurriculumNode", foreign_key: :parent_id, dependent: :restrict_with_error

  validates :kind, inclusion: { in: %w[folder lecture] }
  validates :title, presence: true, length: { maximum: 255 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :request_key, length: { maximum: 100 }, allow_nil: true
  validate :consistent_tree

  scope :ordered, -> { order(:position, :id) }

  private

  def consistent_tree
    errors.add(:lecture, "must match node kind") unless (kind == "lecture") == lecture.present?
    return unless parent

    errors.add(:parent, "must be a folder in the same subject") unless parent.kind == "folder" && parent.branch_id == branch_id
    seen = {}
    cursor = parent
    while cursor
      if cursor.id == id || seen[cursor.id]
        errors.add(:parent, "cannot be this folder or one of its descendants")
        break
      end
      seen[cursor.id] = true
      cursor = cursor.parent
    end
  end
end
