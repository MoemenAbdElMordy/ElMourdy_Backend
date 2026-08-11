require "test_helper"

class Api::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "returns only the authenticated student profile" do
    student = create_student
    token = session_token_for(student.user)

    get "/api/profile", headers: authorization_header(token)

    assert_response :success
    assert_equal student.user_id, response.parsed_body.dig("user", "id")
    assert_equal student.parent_phone_e164, response.parsed_body.dig("profile", "parent_phone")
    assert_empty response.parsed_body["linked_students"]
  end

  test "returns only students linked to the authenticated parent" do
    parent_phone = unique_phone
    linked_student = create_student(parent_phone:)
    linked_student.update!(school: "Test School")
    year, grade = create_academic_setup
    StudentEnrollment.create!(
      student_profile: linked_student, academic_year: year, grade:,
      status: :active, enrolled_at: Time.current
    )
    session_token_for(linked_student.user)
    create_student
    parent = create_parent(phone: parent_phone)
    ParentLinks::Sync.call(parent_profile: parent)
    token = session_token_for(parent.user)

    get "/api/profile", headers: authorization_header(token)

    assert_response :success
    assert_equal [ linked_student.id ], response.parsed_body["linked_students"].pluck("id")
    assert_equal grade.name, response.parsed_body.dig("linked_students", 0, "grade")
    assert_equal "Test School", response.parsed_body.dig("linked_students", 0, "school")
    assert response.parsed_body.dig("linked_students", 0, "last_active_at").present?
  end

  test "changes password and ends other sessions" do
    user = create_user(role: :parent)
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    current_token = session_token_for(user)
    other_session = UserSession.create!(
      user:,
      session_token_digest: Security::DigestValue.call("other-token"),
      status: :active,
      started_at: Time.current,
      last_seen_at: Time.current
    )

    patch "/api/profile/password", params: {
      profile: {
        current_password: "ValidPassword123!",
        password: "NewValidPassword123!",
        password_confirmation: "NewValidPassword123!"
      }
    }, headers: authorization_header(current_token), as: :json

    assert_response :no_content
    assert user.reload.authenticate("NewValidPassword123!")
    assert other_session.reload.ended?
  end

  test "rejects unauthenticated profile access" do
    get "/api/profile"

    assert_response :unauthorized
  end

  test "returns only enabled assistant permission keys" do
    user = create_user(role: :assistant)
    profile = AssistantProfile.create!(user:, title: "Support")
    profile.assistant_permissions.create!(permission_key: "manage_students", enabled: true)
    profile.assistant_permissions.create!(permission_key: "manage_content", enabled: false)
    token = session_token_for(user)

    get "/api/profile", headers: authorization_header(token)

    assert_response :success
    assert_equal [ "manage_students" ], response.parsed_body.dig("user", "permissions")
  end

  private

  def session_token_for(user)
    device = if user.student?
      Devices::Register.call(
        student_profile: user.student_profile,
        fingerprint: SecureRandom.uuid,
        attributes: {}
      )
    end
    Sessions::Start.call(user:, device_registration: device).raw_token
  end

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
