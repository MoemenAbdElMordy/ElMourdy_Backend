class ExamQuestion < ApplicationRecord
  belongs_to :exam
  has_many :exam_choices, -> { order(:position) }, dependent: :restrict_with_error
  has_many :exam_answers, dependent: :restrict_with_error

  validates :body, presence: true
  validates :points, numericality: { greater_than: 0 }
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :exam_id }
  validate :published_exam_has_valid_choice_set

  private

  def published_exam_has_valid_choice_set
    return unless exam&.published? && exam_choices.loaded?
    return if exam_choices.size >= 2 && exam_choices.count(&:is_correct?) == 1

    errors.add(:exam_choices, "must contain at least two choices and exactly one correct choice")
  end
end
