require "test_helper"

class Api::DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "student dashboard returns persisted progress and curriculum counts" do
    year, grade, _branch, _chapter, lesson = create_curriculum
    lecture = lesson.lectures.create!(title: "Recorded lecture", position: 1, status: :published)
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, enrolled_at: Time.current)
    device = student.device_registrations.create!(
      device_fingerprint_digest: Security::DigestValue.call(SecureRandom.hex(8)), status: :active
    )
    student.lecture_watch_events.create!(
      lecture:, device_registration: device, started_at: 1.hour.ago, completed_at: Time.current
    )
    token = Sessions::Start.call(user: student.user, device_registration: device).raw_token

    get "/api/dashboard", headers: auth(token)

    assert_response :success
    assert_equal 1, response.parsed_body.dig("dashboard", "statistics", "completed_lectures")
    assert_equal "Grammar", response.parsed_body.dig("dashboard", "subjects", 0, "title")
  end

  test "teacher dashboard returns real student and content totals" do
    teacher = create_user(role: :teacher)
    create_student
    token = Sessions::Start.call(user: teacher).raw_token

    get "/api/dashboard", headers: auth(token)

    assert_response :success
    assert_equal User.student.count, response.parsed_body.dig("dashboard", "statistics", "total_students")
  end

  test "assistant can load the operational dashboard" do
    assistant = create_user(role: :assistant)
    AssistantProfile.create!(user: assistant)
    token = Sessions::Start.call(user: assistant).raw_token

    get "/api/dashboard", headers: auth(token)

    assert_response :success
    assert_equal "assistant", response.parsed_body.dig("dashboard", "role")
  end

  private

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
