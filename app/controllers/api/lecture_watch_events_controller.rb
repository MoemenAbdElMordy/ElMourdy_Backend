module Api
  class LectureWatchEventsController < ApplicationController
    before_action :authenticate_user!

    def update
      return render_forbidden unless current_user.student?

      event = current_user.student_profile.lecture_watch_events.find(params[:id])
      now = Time.current
      accepted_seconds = 0

      event.with_lock do
        position = bounded_position(event.lecture, params.require(:position_seconds))
        accepted_seconds = accepted_watch_seconds(event, params.fetch(:watched_seconds_delta, 0), now)
        event.update!(
          last_position_seconds: position,
          watched_seconds: event.watched_seconds + accepted_seconds,
          last_heartbeat_at: now
        )
        mark_completed!(event, now)
      end

      total_watched = verified_watched_seconds(event)
      render json: {
        watch_event: event.as_json(only: %i[id last_position_seconds watched_seconds completed_at]).merge(
          verified_watched_seconds: total_watched,
          accepted_seconds: accepted_seconds,
          progress_percent: progress_percent(event.lecture, total_watched)
        )
      }
    end

    private

    def bounded_position(lecture, requested_position)
      position = [ requested_position.to_i, 0 ].max
      return position unless lecture.duration_seconds.present?

      [ position, lecture.duration_seconds ].min
    end

    def accepted_watch_seconds(event, requested_delta, now)
      return 0 unless latest_watch_event?(event)

      requested = [ requested_delta.to_i, 0 ].max
      elapsed = event.last_heartbeat_at ? (now - event.last_heartbeat_at).floor : 0
      [ requested, elapsed, 20 ].min
    end

    def latest_watch_event?(event)
      event.student_profile.lecture_watch_events.where(lecture: event.lecture)
        .order(created_at: :desc, id: :desc).limit(1).pick(:id) == event.id
    end

    def verified_watched_seconds(event)
      event.student_profile.lecture_watch_events.where(lecture: event.lecture).sum(:watched_seconds)
    end

    def mark_completed!(event, now)
      return if event.completed_at.present?

      total_watched = verified_watched_seconds(event)
      threshold = completion_threshold(event.lecture)
      event.update!(completed_at: now) if threshold && total_watched >= threshold
    end

    def completion_threshold(lecture)
      return unless lecture.duration_seconds.present?

      (lecture.duration_seconds * 0.9).ceil
    end

    def progress_percent(lecture, watched_seconds)
      return 0 unless lecture.duration_seconds.to_i.positive?

      [ (watched_seconds.to_f / lecture.duration_seconds * 100).round, 100 ].min
    end
  end
end
