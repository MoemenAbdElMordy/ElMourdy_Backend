class AddLearningPageFieldsToLectures < ActiveRecord::Migration[8.1]
  def change
    change_table :lectures, bulk: true do |table|
      table.text :description
      table.string :attachment_name
      table.string :attachment_url, limit: 2048
      table.string :thumbnail_key
    end
  end
end
