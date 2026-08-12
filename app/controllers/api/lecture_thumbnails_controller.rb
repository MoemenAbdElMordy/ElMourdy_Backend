require "tempfile"

module Api
  class LectureThumbnailsController < ApplicationController
    MAX_FILE_SIZE = 5.megabytes
    CONTENT_TYPES = {
      "image/jpeg" => ".jpg",
      "image/png" => ".png",
      "image/webp" => ".webp"
    }.freeze

    before_action :authenticate_user!

    def show
      return render_not_found unless lecture.thumbnail_key.present?
      return render_forbidden unless allowed_to_view?
      expires_in 1.hour, public: false
      return unless stale?(etag: lecture.thumbnail_key, last_modified: lecture.updated_at, public: false)

      send_data storage.read(lecture.thumbnail_key), type: thumbnail_content_type,
        disposition: "inline", filename: File.basename(lecture.thumbnail_key)
    end

    def update
      require_teacher_or_assistant_permission!("manage_content")
      return if performed?

      content_type = request.media_type
      extension = CONTENT_TYPES[content_type]
      raise ApplicationService::Error, "The thumbnail type is not supported" unless extension
      raise ApplicationService::Error, "The thumbnail exceeds the 5 MB limit" if request.content_length.to_i > MAX_FILE_SIZE

      old_key = lecture.thumbnail_key
      new_key = "thumbnails/lectures/#{lecture.id}/#{SecureRandom.uuid}#{extension}"
      Tempfile.create([ "lecture-thumbnail", extension ], binmode: true) do |file|
        IO.copy_stream(request.body, file)
        file.flush
        raise ApplicationService::Error, "The thumbnail exceeds the 5 MB limit" if file.size > MAX_FILE_SIZE

        storage.upload_file(new_key, file.path, content_type:)
      end
      lecture.update!(thumbnail_key: new_key)
      storage.delete(old_key) if old_key.present? && old_key != new_key
      render json: { thumbnail: { lecture_id: lecture.id, has_thumbnail: true } }
    end

    def destroy
      require_teacher_or_assistant_permission!("manage_content")
      return if performed?

      storage.delete(lecture.thumbnail_key) if lecture.thumbnail_key.present?
      lecture.update!(thumbnail_key: nil)
      head :no_content
    end

    private

    def lecture
      @lecture ||= Lecture.includes(lesson: { chapter: :branch }).find(params[:lecture_id])
    end

    def storage = @storage ||= Videos::Storage.build

    def allowed_to_view?
      return true if current_user.teacher?
      return current_user.assistant_profile.present? if current_user.assistant?

      Videos::Access.allowed?(user: current_user, lecture:)
    end

    def thumbnail_content_type
      Rack::Mime.mime_type(File.extname(lecture.thumbnail_key), "image/jpeg")
    end
  end
end
