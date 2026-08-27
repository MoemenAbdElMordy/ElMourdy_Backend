class AddCenterNameToStudentProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :student_profiles, :center_name, :string
  end
end
