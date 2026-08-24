module Curriculum
  class DestroyLecture
    def self.call(lecture)
      removable_assets = []
      thumbnail_key = lecture.thumbnail_key

      Lecture.transaction do
        lecture.update_column(:selected_video_asset_id, nil) if lecture.selected_video_asset_id?
        lecture.video_assets.find_each do |asset|
          replacement_lecture = asset.selected_by_lectures.where.not(id: lecture.id).first
          if replacement_lecture
            asset.update!(lecture: replacement_lecture)
          else
            removable_assets << asset
            asset.destroy!
          end
        end
        LectureWatchEvent.where(lecture_id: lecture.id).delete_all
        lecture.destroy!
      end

      removable_assets.each { |asset| delete_asset_files(asset) }
      Videos::Storage.build.delete(thumbnail_key) if thumbnail_key.present?
    end

    def self.delete_asset_files(asset)
      prefix = File.dirname(File.dirname(asset.original_file_key))
      Videos::Storage.build.delete_prefix(prefix)
      Videos::Storage.staging.delete_prefix(prefix)
      Videos::Storage.delivery_cache.delete_prefix(prefix)
    end
    private_class_method :delete_asset_files
  end
end
