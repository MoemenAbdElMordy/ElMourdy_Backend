class StudentParentLink < ApplicationRecord
  enum :relation, { father: 0, mother: 1, guardian: 2, other: 3 }, validate: true
  enum :status, { active: 0, removed: 1 }, validate: true

  belongs_to :student_profile
  belongs_to :parent_profile

  validates :linked_at, presence: true
  validates :student_profile_id, uniqueness: { scope: :parent_profile_id }

  scope :current, -> { active.order(linked_at: :asc) }
end
