class CreateCurriculumNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :curriculum_nodes do |t|
      t.references :branch, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :curriculum_nodes }
      t.references :lecture, foreign_key: true
      t.references :legacy_chapter, foreign_key: { to_table: :chapters }
      t.references :legacy_lesson, foreign_key: { to_table: :lessons }
      t.string :kind, null: false, default: "folder"
      t.string :title, null: false
      t.integer :position, null: false
      t.string :request_key
      t.timestamps
    end
    add_index :curriculum_nodes, [:branch_id, :parent_id, :position], name: "idx_curriculum_node_siblings"
    add_index :curriculum_nodes, [:branch_id, :request_key], unique: true, name: "idx_curriculum_node_request"
    add_index :curriculum_nodes, :legacy_chapter_id, unique: true, name: "idx_curriculum_node_legacy_chapter"
    add_index :curriculum_nodes, :legacy_lesson_id, unique: true, name: "idx_curriculum_node_legacy_lesson"
    add_index :curriculum_nodes, [:parent_id, :lecture_id], unique: true, name: "idx_curriculum_node_lecture_placement"
  end
end
