module Api
  class LectureWatchEventsController < ApplicationController
    before_action :authenticate_user!

    def update
      return render_forbidden unless current_user.student?

      event = current_user.student_profile.lecture_watch_events.find(params[:id])
      position = [ params.require(:position_seconds).to_i, event.lecture.duration_seconds.to_i ].min
      attributes = { last_position_seconds: [ position, 0 ].max }
      attributes[:completed_at] = Time.current if completed?(event.lecture, position)
      event.update!(attributes)
      render json: { watch_event: event.as_json(only: %i[id last_position_seconds completed_at]) }
    end

    private

    def completed?(lecture, position)
      lecture.duration_seconds.present? && position >= (lecture.duration_seconds * 0.9).floor
    end
  end
end
