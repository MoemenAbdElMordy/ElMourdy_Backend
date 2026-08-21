module Api
  class VideoPlaybacksController < ApplicationController
    before_action :authenticate_user!

    def show
      lecture = Lecture.includes(lesson: { chapter: :branch }, video_assets: :video_variants).find(params[:lecture_id])
      return render_forbidden unless Videos::Access.allowed?(user: current_user, lecture:)

      asset = lecture.video_assets.ready.order(created_at: :desc).first
      return render json: { error: { code: "video_not_ready", message: "The video is not ready for playback" } }, status: :conflict unless asset

      token = Videos::PlaybackToken.issue(video_asset: asset, viewer: current_user)
      event = current_user.student? ? start_watch_event(lecture) : nil
      render json: {
        playback: {
          lecture: lecture.as_json(only: %i[id title description attachment_name attachment_url duration_seconds]).merge(
            has_thumbnail: lecture.thumbnail_key.present?
          ),
          video_asset_id: asset.id,
          qualities: playback_urls(asset, token),
          watch_event_id: event&.id,
          last_position_seconds: event&.last_position_seconds.to_i,
          watched_seconds: verified_watched_seconds(lecture),
          watermark: watermark
        }
      }
    end

    private

    def start_watch_event(lecture)
      current_user.student_profile.lecture_watch_events.create!(
        lecture:,
        device_registration: current_session.device_registration,
        started_at: Time.current,
        last_heartbeat_at: Time.current,
        last_position_seconds: previous_position(lecture),
        completed_at: previous_completion(lecture),
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def previous_position(lecture)
      current_user.student_profile.lecture_watch_events.where(lecture:).order(created_at: :desc).pick(:last_position_seconds).to_i
    end

    def previous_completion(lecture)
      current_user.student_profile.lecture_watch_events.where(lecture:).where.not(completed_at: nil).minimum(:completed_at)
    end

    def verified_watched_seconds(lecture)
      return 0 unless current_user.student?

      current_user.student_profile.lecture_watch_events.where(lecture:).sum(:watched_seconds)
    end

    def playback_urls(asset, token)
      base = ENV["MEDIA_DELIVERY_BASE_URL"].presence if Rails.env.production?
      asset.video_variants.ready.each_with_object({}) do |variant, result|
        path = variant.file_key.split("/hls/", 2).last
        result[variant.quality] = if base
          "#{base.delete_suffix("/")}/#{asset.id}/#{token}/#{path}"
        else
          api_video_delivery_url(video_asset_id: asset.id, token:, path:)
        end
      end
    end

    def watermark
      return unless current_user.student?

      {
        name: current_user.name,
        phone: current_user.phone_e164.sub(/\d{4}\z/, "****"),
        viewer_id: current_user.id
      }
    end
  end
end
