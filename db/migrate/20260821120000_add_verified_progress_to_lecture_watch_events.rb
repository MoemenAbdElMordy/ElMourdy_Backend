class AddVerifiedProgressToLectureWatchEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :lecture_watch_events, :watched_seconds, :integer, null: false, default: 0
    add_column :lecture_watch_events, :last_heartbeat_at, :datetime

    add_check_constraint :lecture_watch_events, "watched_seconds >= 0", name: "chk_watch_seconds"
  end
end
