class ExamGradeAssignment < ApplicationRecord
  belongs_to :exam
  belongs_to :grade

  validates :grade_id, uniqueness: { scope: :exam_id }
end
