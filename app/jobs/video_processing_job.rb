require "tmpdir"
require "aws-sdk-s3"

class VideoProcessingJob < ApplicationJob
  queue_as :video_processing
  limits_concurrency to: 1, key: ->(video_asset_id) { video_asset_id }, duration: 6.hours
  retry_on Aws::S3::Errors::ServiceError, wait: :polynomially_longer, attempts: 5

  def perform(video_asset_id)
    asset = VideoAsset.find(video_asset_id)
    return if processing_complete?(asset)

    asset.update!(processing_status: :processing)
    staging = Videos::Storage.staging
    storage = Videos::Storage.build
    staged_input = staging.path_for(asset.original_file_key)
    raise "The staged original video is missing" unless staged_input.file?

    Dir.mktmpdir("video-#{asset.id}-", Rails.root.join("tmp")) do |directory|
      root = Pathname(directory)
      input = root.join("source")
      output = root.join("hls")
      File.link(staged_input, input)
      Videos::Transcoder.new(input:, output_root: output).call do |quality, duration|
        upload_variant(asset, storage, output, quality)
        publish_available_quality(asset, quality, duration)
      end
      staging.delete(asset.original_file_key)
    end
  rescue StandardError => error
    status = asset&.video_variants&.ready&.exists? ? :ready : :failed
    asset&.update_columns(processing_status: VideoAsset.processing_statuses.fetch(status))
    Rails.logger.error("Video processing failed for asset #{video_asset_id}: #{error.class}: #{error.message}")
    raise
  end

  private

  def processing_complete?(asset)
    asset.ready? && (Videos::Transcoder::QUALITIES.keys - Array(asset.available_qualities)).empty?
  end

  def upload_variant(asset, storage, output, quality)
    prefix = "#{File.dirname(File.dirname(asset.original_file_key))}/hls"
    quality_root = output.join(quality)
    paths = quality_root.children.sort
    errors = Queue.new
    paths.each_slice((paths.size / 8.0).ceil).map do |batch|
      Thread.new do
        batch.each do |path|
          begin
            key = "#{prefix}/#{quality}/#{path.basename}"
            content_type = path.extname == ".m3u8" ? "application/vnd.apple.mpegurl" : "video/mp2t"
            storage.upload_file(key, path, content_type:)
          rescue StandardError => error
            errors << error
            break
          end
        end
      end
    end.each(&:join)
    raise errors.pop unless errors.empty?
    cache_variant(paths, prefix, quality) if Rails.env.development?

    playlist_key = "#{prefix}/#{quality}/index.m3u8"
    variant = asset.video_variants.find_or_initialize_by(quality:)
    variant.update!(file_key: playlist_key, status: :ready, size_bytes: paths.sum(&:size))
  end

  def publish_available_quality(asset, quality, duration)
    qualities = (Array(asset.available_qualities) + [ quality ]).uniq
    asset.update!(processing_status: :ready, duration_seconds: duration, available_qualities: qualities)
    asset.lecture.update!(duration_seconds: duration)
  end

  def cache_variant(paths, prefix, quality)
    cache = Videos::Storage.delivery_cache
    paths.each do |path|
      key = "#{prefix}/#{quality}/#{path.basename}"
      content_type = path.extname == ".m3u8" ? "application/vnd.apple.mpegurl" : "video/mp2t"
      cache.upload_file(key, path, content_type:)
    end
  end
end
