require "test_helper"

class Api::AuthenticationJourneyTest < ActionDispatch::IntegrationTest
  test "student can register verify log in reset password and log in again" do
    _year, grade = create_academic_setup
    phone = "01012345678"
    email = "journey.student@example.test"

    post "/api/registrations/student", params: { registration: {
      name: "Journey Student", phone:, parent_phone: "01112345678", birth_date: "2008-04-16",
      governorate: "Cairo", school: "Test School", center_name: "Test Center",
      email:, grade_level: grade.level,
      password: "ValidPassword123!", password_confirmation: "ValidPassword123!"
    } }, as: :json
    assert_response :created
    registration = response.parsed_body
    registration_code = ActionMailer::Base.deliveries.last.body.encoded.match(/\b\d{6}\b/).to_s

    post "/api/registrations/#{registration.fetch('registration_id')}/verify", params: { registration: {
      verification_id: registration.fetch("verification_id"), code: registration_code,
      device_fingerprint: "journey-device"
    } }, as: :json
    assert_response :success
    first_token = response.parsed_body.fetch("token")

    delete "/api/session", headers: { "Authorization" => "Bearer #{first_token}" }
    assert_response :no_content
    post "/api/session", params: { session: { phone:, password: "ValidPassword123!", device_fingerprint: "journey-device" } }, as: :json
    assert_response :created
    active_token = response.parsed_body.fetch("token")

    post "/api/password_resets", params: { password_reset: { email: } }, as: :json
    assert_response :created
    reset = response.parsed_body
    reset_code = ActionMailer::Base.deliveries.last.text_part.body.decoded.match(/\d{6}/).to_s
    post "/api/password_resets/#{reset.fetch('password_reset_id')}/verify", params: { password_reset: {
      client_token: reset.fetch("client_token"), code: reset_code
    } }, as: :json
    assert_response :success
    patch "/api/password_resets/#{reset.fetch('password_reset_id')}", params: { password_reset: {
      client_token: reset.fetch("client_token"), password: "NewValidPassword123!",
      password_confirmation: "NewValidPassword123!"
    } }, as: :json
    assert_response :no_content

    get "/api/session", headers: { "Authorization" => "Bearer #{active_token}" }
    assert_response :unauthorized
    post "/api/session", params: { session: { phone:, password: "ValidPassword123!", device_fingerprint: "journey-device" } }, as: :json
    assert_response :unauthorized
    post "/api/session", params: { session: { phone:, password: "NewValidPassword123!", device_fingerprint: "journey-device" } }, as: :json
    assert_response :created
  end
end
