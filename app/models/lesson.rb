class Lesson < ApplicationRecord
  include Publishable

  belongs_to :chapter
  belongs_to :required_exam, class_name: "Exam", optional: true
  has_many :lectures, dependent: :restrict_with_error
  has_many :exams, dependent: :restrict_with_error
  has_many :activation_code_batches, dependent: :restrict_with_error
  has_many :lesson_access_grants, dependent: :restrict_with_error

  validates :title, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :chapter_id }
  validates :pass_required_percent, numericality: {
    only_integer: true, in: 0..100
  }, allow_nil: true
  validate :exam_requirement_is_complete

  private

  def exam_requirement_is_complete
    complete = required_exam_id.present? && pass_required_percent.present?
    return if requires_exam_pass ? complete : !complete

    errors.add(:requires_exam_pass, "must match the required exam configuration")
  end
end
