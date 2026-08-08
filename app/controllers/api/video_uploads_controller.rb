module Api
  class VideoUploadsController < ApplicationController
    MAX_FILE_SIZE = 6.gigabytes
    ALLOWED_CONTENT_TYPES = %w[video/mp4 video/quicktime video/x-matroska video/webm].freeze

    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("upload_videos") }

    def create
      validate_upload!
      asset = lecture.video_assets.create!(
        original_file_key: original_key,
        processing_status: :uploaded,
        created_by_user: current_user
      )
      render json: { video_asset: serialize(asset), upload: upload_payload(asset) }, status: :created
    end

    def content
      storage = Videos::Storage.build
      return render json: { error: { code: "not_found", message: "Local upload is unavailable" } }, status: :not_found unless storage.local?

      asset = lecture.video_assets.find(params.require(:video_asset_id))
      storage.put(asset.original_file_key, request.body)
      head :no_content
    end

    def complete
      asset = lecture.video_assets.find(params.require(:video_asset_id))
      storage = Videos::Storage.build
      raise ApplicationService::Error, "The uploaded video could not be found" unless storage.exist?(asset.original_file_key)
      raise ApplicationService::Error, "The uploaded video exceeds the 6 GB limit" if storage.size(asset.original_file_key) > MAX_FILE_SIZE

      VideoProcessingJob.perform_later(asset.id)
      render json: { video_asset: serialize(asset) }, status: :accepted
    end

    private

    def lecture = @lecture ||= Lecture.find(params[:lecture_id])

    def validate_upload!
      raise ApplicationService::Error, "A video file name is required" if params[:filename].blank?
      raise ApplicationService::Error, "The video type is not supported" unless ALLOWED_CONTENT_TYPES.include?(params[:content_type])
      raise ApplicationService::Error, "The uploaded video exceeds the 6 GB limit" if params[:size_bytes].to_i > MAX_FILE_SIZE
    end

    def original_key
      extension = File.extname(params[:filename].to_s).downcase
      "videos/#{SecureRandom.uuid}/original/source#{extension}"
    end

    def upload_payload(asset)
      storage = Videos::Storage.build
      if storage.local?
        {
          url: content_api_lecture_video_upload_url(lecture, video_asset_id: asset.id),
          method: "PUT",
          headers: { "Content-Type" => params[:content_type] },
          requires_authentication: true
        }
      else
        {
          url: storage.presigned_put(asset.original_file_key, content_type: params[:content_type]),
          method: "PUT",
          headers: { "Content-Type" => params[:content_type] },
          requires_authentication: false
        }
      end
    end

    def serialize(asset)
      asset.as_json(only: %i[id lecture_id processing_status duration_seconds available_qualities created_at])
    end
  end
end
