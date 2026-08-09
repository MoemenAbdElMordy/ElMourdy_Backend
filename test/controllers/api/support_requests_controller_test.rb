require "test_helper"

class Api::SupportRequestsControllerTest < ActionDispatch::IntegrationTest
  test "teacher approval grants one additional exam attempt" do
    exam = create_exam
    exam.update!(max_attempts: 1)
    student = create_student
    student_token = start_test_session(student.user).raw_token
    teacher = create_user(role: :teacher)
    teacher_token = Sessions::Start.call(user: teacher).raw_token
    ExamAttempts::Start.call(exam:, student_profile: student)

    post "/api/support_requests", params: {
      support_request: { request_type: "extra_exam_attempt", reason: "I need another attempt", payload: { exam_id: exam.id } }
    }, headers: auth(student_token), as: :json
    assert_response :created
    request_id = response.parsed_body.dig("support_request", "id")

    post "/api/support_requests/#{request_id}/review", params: { decision: "approve", note: "Approved" }, headers: auth(teacher_token), as: :json
    assert_response :success
    assert_equal "approved", response.parsed_body.dig("support_request", "status")
    assert ExamAttempts::Start.call(exam:, student_profile: student).persisted?
  end

  private

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
