class Grade < ApplicationRecord
  include CatalogCacheable
  has_many :student_enrollments, dependent: :restrict_with_error
  has_many :branches, dependent: :restrict_with_error
  has_many :exams, dependent: :restrict_with_error

  validates :name, presence: true
  validates :level, inclusion: { in: 1..3 }, uniqueness: true

  scope :enabled, -> { where(active: true).order(:level) }
end
