require "tmpdir"

class VideoProcessingJob < ApplicationJob
  queue_as :video_processing

  def perform(video_asset_id)
    asset = VideoAsset.find(video_asset_id)
    asset.update!(processing_status: :processing)
    storage = Videos::Storage.build

    Dir.mktmpdir("video-#{asset.id}-") do |directory|
      root = Pathname(directory)
      input = root.join("original#{File.extname(asset.original_file_key)}")
      output = root.join("hls")
      storage.download(asset.original_file_key, input)
      duration = Videos::Transcoder.new(input:, output_root: output).call
      upload_variants(asset, storage, output)
      qualities = Videos::Transcoder::QUALITIES.keys
      asset.update!(processing_status: :ready, duration_seconds: duration, available_qualities: qualities)
      asset.lecture.update!(duration_seconds: duration)
      storage.delete(asset.original_file_key) if ENV.fetch("DELETE_VIDEO_ORIGINALS", "true") == "true"
    end
  rescue StandardError => error
    asset&.update_columns(processing_status: VideoAsset.processing_statuses[:failed])
    Rails.logger.error("Video processing failed for asset #{video_asset_id}: #{error.class}: #{error.message}")
    raise
  end

  private

  def upload_variants(asset, storage, output)
    prefix = "#{File.dirname(File.dirname(asset.original_file_key))}/hls"
    Videos::Transcoder::QUALITIES.each_key do |quality|
      quality_root = output.join(quality)
      quality_root.children.sort.each do |path|
        key = "#{prefix}/#{quality}/#{path.basename}"
        content_type = path.extname == ".m3u8" ? "application/vnd.apple.mpegurl" : "video/mp2t"
        storage.upload_file(key, path, content_type:)
      end
      playlist_key = "#{prefix}/#{quality}/index.m3u8"
      variant = asset.video_variants.find_or_initialize_by(quality:)
      variant.update!(file_key: playlist_key, status: :ready, size_bytes: quality_root.children.sum(&:size))
    end
  end
end
