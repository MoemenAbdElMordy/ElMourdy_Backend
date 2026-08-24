module Api
  class VideoAssetsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("upload_videos") }

    def index
      assets = VideoAsset.ready.includes(:lecture, :video_variants, :selected_by_lectures).order(created_at: :desc)
      assets, pagination = paginate(assets)
      render json: { video_assets: assets.map { |asset| serialize(asset) }, pagination: }
    end

    def show
      render json: { video_asset: serialize(video_asset) }
    end

    def destroy
      references = video_asset.selected_by_lectures
      raise ApplicationService::Error, "The video is used by another lecture" if references.where.not(id: video_asset.lecture_id).exists?
      references.update_all(selected_video_asset_id: nil)

      prefix = File.dirname(File.dirname(video_asset.original_file_key))
      Videos::Storage.build.delete_prefix(prefix)
      Videos::Storage.staging.delete_prefix(prefix)
      Videos::Storage.delivery_cache.delete_prefix(prefix)
      video_asset.destroy!
      head :no_content
    end

    def retry_processing
      storage = Videos::Storage.staging
      raise ApplicationService::Error, "The original video is no longer available; upload it again" unless storage.exist?(video_asset.original_file_key)
      if video_asset.ready? && (Videos::Transcoder::QUALITIES.keys - Array(video_asset.available_qualities)).empty?
        raise ApplicationService::Error, "A ready video does not need processing"
      end

      video_asset.update!(processing_status: :uploaded)
      Videos::ProcessingDispatcher.call(video_asset.id)
      render json: { video_asset: serialize(video_asset) }, status: :accepted
    end

    private

    def video_asset = @video_asset ||= VideoAsset.includes(:video_variants).find(params[:id])

    def serialize(asset)
      references = asset.selected_by_lectures
      asset.as_json(only: %i[id lecture_id processing_status duration_seconds available_qualities created_at]).merge(
        lecture_title: asset.lecture.title,
        storage_size_bytes: asset.video_variants.sum { |variant| variant.size_bytes.to_i },
        used_by_lectures_count: references.size,
        can_delete: references.none? { |lecture| lecture.id != asset.lecture_id },
        variants: asset.video_variants.map { |variant| variant.as_json(only: %i[quality status size_bytes]) }
      )
    end
  end
end
