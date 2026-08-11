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

  test "approving device removal removes the device and revokes its sessions" do
    student = create_student
    session = start_test_session(student.user)
    device = session.session.device_registration
    teacher = create_user(role: :teacher)
    teacher_token = Sessions::Start.call(user: teacher).raw_token
    request_record = student.user.support_requests.create!(
      student_profile: student, request_type: :device_removal, reason: "Old device",
      payload: { device_registration_id: device.id }
    )

    post "/api/support_requests/#{request_record.id}/review", params: { decision: "approve" },
      headers: auth(teacher_token), as: :json

    assert_response :success
    assert device.reload.removed?
    assert session.session.reload.revoked?
  end

  test "approving a parent phone change updates the student and parent link" do
    student = create_student
    parent = create_parent
    teacher = create_user(role: :teacher)
    teacher_token = Sessions::Start.call(user: teacher).raw_token
    request_record = student.user.support_requests.create!(
      student_profile: student, request_type: :parent_phone_change, reason: "New guardian phone",
      payload: { new_parent_phone: parent.user.phone_e164 }
    )

    post "/api/support_requests/#{request_record.id}/review", params: { decision: "approve" },
      headers: auth(teacher_token), as: :json

    assert_response :success
    assert_equal parent.user.phone_e164, student.reload.parent_phone_e164
    assert student.student_parent_links.active.exists?(parent_profile: parent)
  end

  test "assistant needs the request-specific permission to approve" do
    student = create_student
    assistant = create_user(role: :assistant)
    profile = AssistantProfile.create!(user: assistant)
    profile.assistant_permissions.create!(permission_key: "manage_support_requests", enabled: true)
    token = Sessions::Start.call(user: assistant).raw_token
    request_record = student.user.support_requests.create!(
      student_profile: student, request_type: :extra_exam_attempt, payload: { exam_id: 1 }
    )

    post "/api/support_requests/#{request_record.id}/review", params: { decision: "approve" },
      headers: auth(token), as: :json

    assert_response :forbidden
    assert request_record.reload.pending?
  end

  private

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
