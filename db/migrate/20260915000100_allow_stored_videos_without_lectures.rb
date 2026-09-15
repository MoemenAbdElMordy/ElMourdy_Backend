class AllowStoredVideosWithoutLectures < ActiveRecord::Migration[8.1]
  def change
    change_column_null :video_assets, :lecture_id, true
  end
end
