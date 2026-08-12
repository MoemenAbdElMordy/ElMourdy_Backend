class AcademicYear < ApplicationRecord
  include CatalogCacheable
  enum :status, { draft: 0, active: 1, archived: 2 }, validate: true

  belongs_to :copied_from_year, class_name: "AcademicYear", optional: true
  has_many :copied_years, class_name: "AcademicYear", foreign_key: :copied_from_year_id,
    inverse_of: :copied_from_year, dependent: :restrict_with_error
  has_many :student_enrollments, dependent: :restrict_with_error
  has_many :branches, dependent: :restrict_with_error
  has_many :exams, dependent: :restrict_with_error
  has_many :lesson_access_grants, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :starts_on, :ends_on, presence: true
  validate :ends_after_start

  scope :chronological, -> { order(starts_on: :desc) }

  private

  def ends_after_start
    return if starts_on.blank? || ends_on.blank? || starts_on < ends_on

    errors.add(:ends_on, "must be after the start date")
  end
end
