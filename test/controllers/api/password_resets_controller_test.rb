require "test_helper"

class Api::PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  test "resets a verified account password through an emailed code" do
    user = create_user(role: :parent).tap { |record| record.update!(email: "reset.parent@example.test") }
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    active_session = start_test_session(user)
    post "/api/password_resets", params: { password_reset: { email: " RESET.PARENT@example.test " } }, as: :json

    assert_response :created
    reset = response.parsed_body
    assert_equal "email_code", reset["verification_method"]
    assert_equal user.email, ActionMailer::Base.deliveries.last.to.first

    post "/api/password_resets/#{reset.fetch('password_reset_id')}/verify", params: {
      password_reset: { client_token: reset.fetch("client_token"), code: delivered_code }
    }, as: :json
    assert_response :success
    assert_equal "verified", response.parsed_body["status"]

    patch "/api/password_resets/#{reset.fetch('password_reset_id')}", params: {
      password_reset: { client_token: reset.fetch("client_token"), password: "NewValidPassword123!", password_confirmation: "NewValidPassword123!" }
    }, as: :json
    assert_response :no_content
    assert user.reload.authenticate("NewValidPassword123!")
    assert active_session.session.reload.ended?
    assert OtpVerification.find(reset.fetch("password_reset_id")).consumed?
  end

  test "rejects an email that does not belong to an active account" do
    post "/api/password_resets", params: { password_reset: { email: "missing@example.test" } }, as: :json
    assert_response :unprocessable_entity
    assert_empty ActionMailer::Base.deliveries
  end

  test "rejects an invalid code and client token" do
    user = create_user(role: :student).tap { |record| record.update!(email: "reset.student@example.test") }
    StudentProfile.create!(user:, birth_date: Date.new(2008, 1, 1), parent_phone_e164: unique_phone, center_name: "Test Center")
    result = EmailVerifications::Request.call(user:, purpose: :password_reset)
    post "/api/password_resets/#{result.verification.id}/verify", params: {
      password_reset: { client_token: result.client_token, code: "000000" }
    }, as: :json
    assert_response :unprocessable_entity
    post "/api/password_resets/#{result.verification.id}/status", params: {
      password_reset: { client_token: "wrong-token" }
    }, as: :json
    assert_response :unprocessable_entity
  end

  test "does not allow a reset verification to be reused" do
    user = create_user(role: :parent).tap { |record| record.update!(email: "single.use@example.test") }
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    result = EmailVerifications::Request.call(user:, purpose: :password_reset)
    OtpVerifications::Verify.call(verification: result.verification, code: delivered_code)
    params = { password_reset: { client_token: result.client_token, password: "NewValidPassword123!", password_confirmation: "NewValidPassword123!" } }
    patch "/api/password_resets/#{result.verification.id}", params:, as: :json
    assert_response :no_content
    patch "/api/password_resets/#{result.verification.id}", params:, as: :json
    assert_response :unprocessable_entity
  end

  private

  def delivered_code
    ActionMailer::Base.deliveries.last.text_part.body.decoded.match(/\d{6}/).to_s
  end
end
