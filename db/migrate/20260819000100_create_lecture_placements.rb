class CreateLecturePlacements < ActiveRecord::Migration[8.1]
  def change
    create_table :lecture_placements do |t|
      t.references :lecture, null: false, foreign_key: true, index: false
      t.references :lesson, null: false, foreign_key: true

      t.timestamps
    end

    add_index :lecture_placements, %i[lecture_id lesson_id], unique: true
  end
end
