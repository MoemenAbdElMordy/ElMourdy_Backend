class Branch < ApplicationRecord
  include Publishable

  belongs_to :academic_year
  belongs_to :grade
  has_many :chapters, dependent: :restrict_with_error
  has_many :exams, dependent: :restrict_with_error

  validates :title, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: %i[academic_year_id grade_id] }
end
