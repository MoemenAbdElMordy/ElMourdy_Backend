class AddHomeworksAndVideoSources < ActiveRecord::Migration[8.1]
  def change
    add_column :exams, :assessment_type, :integer, null: false, default: 0
    add_column :exams, :show_answers_after_submission, :boolean, null: false, default: true
    add_column :exams, :correct_after_each_answer, :boolean, null: false, default: false
    add_index :exams, %i[assessment_type academic_year_id grade_id status], name: "idx_exams_type_year_grade_status"
    add_check_constraint :exams, "assessment_type between 0 and 1", name: "chk_exams_assessment_type"

    add_column :lectures, :video_source_type, :integer, null: false, default: 0
    add_column :lectures, :youtube_video_id, :string
    add_reference :lectures, :selected_video_asset, foreign_key: { to_table: :video_assets }, index: true
    add_check_constraint :lectures, "video_source_type between 0 and 1", name: "chk_lectures_video_source_type"
  end
end
