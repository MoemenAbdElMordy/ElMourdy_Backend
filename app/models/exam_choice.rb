class ExamChoice < ApplicationRecord
  belongs_to :exam_question
  has_many :exam_answers, foreign_key: :selected_choice_id, inverse_of: :selected_choice,
    dependent: :restrict_with_error

  validates :body, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :exam_question_id }
end
