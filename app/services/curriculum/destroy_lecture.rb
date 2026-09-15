module Curriculum
  class DestroyLecture
    def self.call(lecture)
      thumbnail_key = lecture.thumbnail_key

      Lecture.transaction do
        lecture.update_column(:selected_video_asset_id, nil) if lecture.selected_video_asset_id?
        lecture.video_assets.find_each do |asset|
          replacement_lecture = asset.selected_by_lectures.where.not(id: lecture.id).first
          asset.update!(lecture: replacement_lecture)
        end
        LectureWatchEvent.where(lecture_id: lecture.id).delete_all
        lecture.destroy!
      end

      Videos::Storage.build.delete(thumbnail_key) if thumbnail_key.present?
    end
  end
end
