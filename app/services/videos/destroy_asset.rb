module Videos
  class DestroyAsset
    def self.call(video_asset)
      prefix = File.dirname(File.dirname(video_asset.original_file_key))

      VideoAsset.transaction do
        video_asset.selected_by_lectures.update_all(selected_video_asset_id: nil)
        video_asset.destroy!
      end

      Storage.build.delete_prefix(prefix)
      Storage.staging.delete_prefix(prefix)
      Storage.delivery_cache.delete_prefix(prefix)
    end
  end
end
