class CreateLectureAccessGrants < ActiveRecord::Migration[8.1]
  def change
    change_column_null :activation_code_batches, :lesson_id, true
    change_column_null :activation_code_batches, :academic_year_id, true
    change_column_null :activation_code_batches, :grade_id, true

    create_table :lecture_access_grants do |t|
      t.references :student_profile, null: false, foreign_key: true, index: false
      t.references :lecture, null: false, foreign_key: true
      t.references :academic_year, null: false, foreign_key: true
      t.references :activation_code, null: false, foreign_key: true, index: { unique: true }
      t.date :expires_on, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    add_index :lecture_access_grants, %i[student_profile_id lecture_id academic_year_id],
      unique: true, name: "idx_lecture_grant_unique"
    add_index :lecture_access_grants, %i[student_profile_id academic_year_id status expires_on],
      name: "idx_student_active_lecture_grants"
    add_check_constraint :lecture_access_grants, "status BETWEEN 0 AND 2",
      name: "chk_lecture_access_grants_status"
  end
end
