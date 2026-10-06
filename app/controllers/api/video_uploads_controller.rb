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
        expected_size_bytes: params[:size_bytes].to_i,
        processing_status: :uploaded,
        created_by_user: current_user
      )
      render json: { video_asset: serialize(asset), upload: upload_payload(asset) }, status: :created
    end

    def content
      asset = lecture.video_assets.find(params.require(:video_asset_id))
      Videos::Storage.staging.put(asset.original_file_key, request.body)
      head :no_content
    end

    def status
      asset = upload_asset
      path = Videos::Storage.staging.path_for(asset.original_file_key)
      render json: { uploaded_bytes: path.file? ? path.size : 0, expected_size_bytes: asset.expected_size_bytes }
    end

    def chunk
      asset = upload_asset
      expected = asset.expected_size_bytes.to_i
      raise ApplicationService::Error, "The expected video size is missing" unless expected.positive?
      raise ApplicationService::Error, "Video chunk exceeds the 8 MB limit" if request.content_length.to_i > 8.megabytes

      offset = Integer(request.headers["X-Upload-Offset"], exception: false)
      raise ApplicationService::Error, "Invalid upload offset" unless offset && offset >= 0

      path = Videos::Storage.staging.path_for(asset.original_file_key)
      FileUtils.mkdir_p(path.dirname)
      File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        # A new upload may restart at zero, but retries must never duplicate bytes.
        file.truncate(0) if offset.zero?
        raise ApplicationService::Error, "Upload offset does not match the stored file" unless file.size == offset
        raise ApplicationService::Error, "The uploaded video exceeds its declared size" if offset + request.content_length.to_i > expected

        file.seek(offset)
        IO.copy_stream(request.body, file)
        raise ApplicationService::Error, "The uploaded video exceeds its declared size" if file.size > expected
        render json: { uploaded_bytes: file.size, expected_size_bytes: expected }
      end
    end

    def complete
      asset = lecture.video_assets.find(params.require(:video_asset_id))
      storage = Videos::Storage.staging
      raise ApplicationService::Error, "The uploaded video could not be found" unless storage.exist?(asset.original_file_key)
      raise ApplicationService::Error, "The uploaded video exceeds the 6 GB limit" if storage.size(asset.original_file_key) > MAX_FILE_SIZE
      if asset.expected_size_bytes && storage.size(asset.original_file_key) != asset.expected_size_bytes
        raise ApplicationService::Error, "The uploaded video is incomplete"
      end

      lecture.update!(video_source_type: :uploaded, selected_video_asset: asset, youtube_video_id: nil)
      return render json: { video_asset: serialize(asset) }, status: :accepted if asset.processing? || asset.ready?

      Videos::ProcessingDispatcher.call(asset.id)
      render json: { video_asset: serialize(asset) }, status: :accepted
    end

    def youtube
      video_id = youtube_video_id(params.require(:url))
      raise ApplicationService::Error, "The YouTube URL is not valid" unless video_id

      lecture.update!(video_source_type: :youtube, youtube_video_id: video_id, selected_video_asset: nil)
      render json: { lecture: { id: lecture.id, video_source_type: lecture.video_source_type, youtube_video_id: video_id } }
    end

    def reuse
      asset = VideoAsset.ready.find(params.require(:video_asset_id))
      lecture.update!(video_source_type: :uploaded, selected_video_asset: asset, youtube_video_id: nil,
        duration_seconds: asset.duration_seconds)
      render json: { video_asset: serialize(asset) }
    end

    private

    def lecture = @lecture ||= Lecture.find(params[:lecture_id])

    def upload_asset
      asset = lecture.video_assets.find(params.require(:video_asset_id))
      raise ApplicationService::Error, "This upload is already being processed" unless asset.uploaded?
      asset
    end

    def validate_upload!
      raise ApplicationService::Error, "A video file name is required" if params[:filename].blank?
      raise ApplicationService::Error, "The video type is not supported" unless ALLOWED_CONTENT_TYPES.include?(params[:content_type])
      raise ApplicationService::Error, "The uploaded video exceeds the 6 GB limit" if params[:size_bytes].to_i > MAX_FILE_SIZE
      raise ApplicationService::Error, "The video file is empty" if params[:size_bytes].to_i <= 0
    end

    def original_key
      extension = File.extname(params[:filename].to_s).downcase
      "videos/#{SecureRandom.uuid}/original/source#{extension}"
    end

    def youtube_video_id(value)
      raw = value.to_s.strip
      return raw if raw.match?(/\A[A-Za-z0-9_-]{11}\z/)

      uri = URI.parse(raw)
      host = uri.host.to_s.downcase.sub(/\Awww\./, "")
      id = if host == "youtu.be"
        uri.path.split("/").reject(&:blank?).first
      elsif %w[youtube.com m.youtube.com].include?(host)
        uri.path == "/watch" ? Rack::Utils.parse_query(uri.query)["v"] : uri.path.match(%r{\A/(?:embed|shorts)/([^/]+)})&.captures&.first
      end
      id if id&.match?(/\A[A-Za-z0-9_-]{11}\z/)
    rescue URI::InvalidURIError
      nil
    end

    def upload_payload(asset)
      {
        url: content_api_lecture_video_upload_url(lecture, video_asset_id: asset.id),
        method: "PUT",
        headers: { "Content-Type" => params[:content_type] },
        requires_authentication: true,
        chunk_url: chunk_api_lecture_video_upload_url(lecture, video_asset_id: asset.id),
        status_url: status_api_lecture_video_upload_url(lecture, video_asset_id: asset.id)
      }
    end

    def serialize(asset)
      asset.as_json(only: %i[id lecture_id processing_status duration_seconds available_qualities created_at])
    end
  end
end
