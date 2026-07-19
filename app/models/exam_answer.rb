class ExamAnswer < ApplicationRecord
  belongs_to :exam_attempt
  belongs_to :exam_question
  belongs_to :selected_choice, class_name: "ExamChoice", optional: true

  validates :exam_question_id, uniqueness: { scope: :exam_attempt_id }
  validates :points_awarded, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :question_belongs_to_attempt_exam
  validate :choice_belongs_to_question

  private

  def question_belongs_to_attempt_exam
    return if exam_attempt.blank? || exam_question.blank? || exam_attempt.exam_id == exam_question.exam_id

    errors.add(:exam_question, "must belong to the attempted exam")
  end

  def choice_belongs_to_question
    return if selected_choice.blank? || selected_choice.exam_question_id == exam_question_id

    errors.add(:selected_choice, "must belong to the answered question")
  end
end
