class Exam < ApplicationRecord
  enum :scope_type, { lesson: 0, chapter: 1, branch: 2, comprehensive: 3 },
    prefix: :scope, validate: true
  enum :attempt_form_mode, { same_exam: 0, random_per_attempt: 1 }, validate: true
  enum :status, { draft: 0, published: 1, hidden: 2, archived: 3 }, validate: true

  belongs_to :lesson, optional: true
  belongs_to :chapter, optional: true
  belongs_to :branch, optional: true
  belongs_to :academic_year
  belongs_to :grade
  belongs_to :created_by_user, class_name: "User", optional: true
  has_many :exam_questions, -> { order(:position) }, dependent: :restrict_with_error
  has_many :exam_attempts, dependent: :restrict_with_error
  has_many :required_by_lessons, class_name: "Lesson", foreign_key: :required_exam_id,
    inverse_of: :required_exam, dependent: :restrict_with_error

  validates :title, presence: true
  validates :duration_minutes, :max_attempts,
    numericality: { only_integer: true, greater_than: 0 }
  validates :pass_percent, :risk_from_percent, :risk_to_percent,
    numericality: { only_integer: true, in: 0..100 }
  validate :risk_range_is_ordered
  validate :scope_reference_matches_type

  scope :available, -> { published.includes(:academic_year, :grade) }

  private

  def risk_range_is_ordered
    return if risk_from_percent.blank? || risk_to_percent.blank? || risk_from_percent <= risk_to_percent

    errors.add(:risk_to_percent, "must be greater than or equal to the risk start")
  end

  def scope_reference_matches_type
    references = { lesson: lesson_id, chapter: chapter_id, branch: branch_id }
    expected = scope_type&.to_sym
    valid = references.all? { |type, value| type == expected ? value.present? : value.nil? }
    valid = references.values.all?(&:nil?) if expected == :comprehensive
    errors.add(:scope_type, "does not match the supplied scope reference") unless valid
  end
end
