class OperationsMaintenanceJob < ApplicationJob
  queue_as :default

  def perform
    SolidQueue::Job.where.not(finished_at: nil).where(finished_at: ...7.days.ago).delete_all
  end
end
