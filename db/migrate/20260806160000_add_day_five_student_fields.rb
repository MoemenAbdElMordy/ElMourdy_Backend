class AddDayFiveStudentFields < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email, :string
    add_index :users, :email, unique: true
    add_column :student_profiles, :school, :string
  end
end
