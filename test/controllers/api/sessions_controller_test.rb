require "test_helper"

class Api::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "logs in, restores the user, and logs out" do
    user = create_user(role: :teacher, phone: "+201012345678")

    post api_session_url, params: {
      session: { phone: "01012345678", password: "ValidPassword123!" }
    }, as: :json

    assert_response :created
    token = response.parsed_body.fetch("token")
    assert_equal user.id, response.parsed_body.dig("user", "id")
    assert_equal "teacher", response.parsed_body.dig("user", "role")
    assert user.reload.last_login_at.present?

    get api_session_url, headers: authorization_header(token), as: :json
    assert_response :success
    assert_equal user.id, response.parsed_body.dig("user", "id")

    delete api_session_url, headers: authorization_header(token), as: :json
    assert_response :no_content
    assert user.user_sessions.last.ended?

    get api_session_url, headers: authorization_header(token), as: :json
    assert_response :unauthorized
  end

  test "registers a device when a student logs in" do
    student = create_student

    post api_session_url, params: {
      session: {
        phone: student.user.phone_e164,
        password: "ValidPassword123!",
        device_fingerprint: "browser-device-id"
      }
    }, as: :json

    assert_response :created
    assert_equal 1, student.device_registrations.active.count
    assert_equal student.device_registrations.first, student.user.user_sessions.last.device_registration
  end

  test "allows an unverified student to log in but blocks platform data until email verification" do
    student = create_student
    student.user.update!(email: "pending.student@example.test", phone_verified_at: nil)

    post api_session_url, params: {
      session: {
        phone: student.user.phone_e164,
        password: "ValidPassword123!",
        device_fingerprint: "pending-student-device"
      }
    }, as: :json

    assert_response :created
    token = response.parsed_body.fetch("token")
    assert_not response.parsed_body.dig("user", "verified")

    get api_dashboard_url, headers: authorization_header(token), as: :json
    assert_response :forbidden
    assert_equal "account_unverified", response.parsed_body.dig("error", "code")

    post api_account_verification_url, headers: authorization_header(token), as: :json
    assert_response :created
    verification_id = response.parsed_body.fetch("verification_id")
    code = ActionMailer::Base.deliveries.last.body.encoded.match(/\b\d{6}\b/).to_s

    patch api_account_verification_url, params: {
      verification: { verification_id:, code: }
    }, headers: authorization_header(token), as: :json

    assert_response :success
    assert response.parsed_body.dig("user", "verified")

    get api_dashboard_url, headers: authorization_header(token), as: :json
    assert_response :success
  end

  test "returns one generic error for invalid credentials" do
    post api_session_url, params: {
      session: { phone: "01012345678", password: "wrong-password" }
    }, as: :json

    assert_response :unauthorized
    assert_equal "invalid_credentials", response.parsed_body.dig("error", "code")
  end

  test "requires a bearer token for protected session actions" do
    get api_session_url, as: :json

    assert_response :unauthorized
  end

  private

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
