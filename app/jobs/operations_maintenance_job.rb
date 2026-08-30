class OperationsMaintenanceJob < ApplicationJob
  queue_as :default

  def perform
    SolidQueue::Job.where.not(finished_at: nil).where(finished_at: ...7.days.ago).delete_all
    LessonAccessGrant.active.where(expires_on: ...Date.current).update_all(
      status: LessonAccessGrant.statuses[:expired],
      updated_at: Time.current
    )
    LectureAccessGrant.active.where(expires_on: ...Date.current).update_all(
      status: LectureAccessGrant.statuses[:expired],
      updated_at: Time.current
    )
  end
end
