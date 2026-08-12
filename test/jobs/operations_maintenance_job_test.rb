require "test_helper"

class OperationsMaintenanceJobTest < ActiveJob::TestCase
  test "expires outdated lesson access grants" do
    year, _grade, _branch, _chapter, lesson = create_curriculum
    student = create_student
    grant = LessonAccessGrant.create!(
      student_profile: student,
      lesson:,
      academic_year: year,
      source: :manual,
      expires_on: Date.yesterday,
      status: :active
    )

    OperationsMaintenanceJob.perform_now

    assert grant.reload.expired?
  end
end
