class CreateExamGradeAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :exam_grade_assignments do |t|
      t.bigint :exam_id, null: false
      t.bigint :grade_id, null: false

      t.timestamps
    end

    add_foreign_key :exam_grade_assignments, :exams
    add_foreign_key :exam_grade_assignments, :grades
  end
end
