require "test_helper"

class Api::PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  test "resets a verified account password through an inbound WhatsApp message" do
    user = create_user(role: :parent, phone: "+201000000001")
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    active_session = start_test_session(user)

    post "/api/password_resets", params: {
      password_reset: { phone: "01000000001" }
    }, as: :json

    assert_response :created
    reset = response.parsed_body
    assert_equal "whatsapp_inbound", reset["verification_method"]
    message = URI.decode_www_form(URI(reset.fetch("whatsapp_url")).query).to_h.fetch("text")
    assert_match(/\ARESET [A-F0-9]{16}\z/, message)

    WhatsappVerifications::Confirm.call(phone: user.phone_e164, message:, message_id: "reset-message")

    post "/api/password_resets/#{reset.fetch('password_reset_id')}/status", params: {
      password_reset: { client_token: reset.fetch("client_token") }
    }, as: :json
    assert_response :success
    assert_equal "verified", response.parsed_body["status"]

    patch "/api/password_resets/#{reset.fetch('password_reset_id')}", params: {
      password_reset: {
        client_token: reset.fetch("client_token"),
        password: "NewValidPassword123!",
        password_confirmation: "NewValidPassword123!"
      }
    }, as: :json

    assert_response :no_content
    assert user.reload.authenticate("NewValidPassword123!")
    assert active_session.session.reload.ended?
    assert OtpVerification.find(reset.fetch("password_reset_id")).consumed?
  end

  test "returns the same reset shape for an unknown phone" do
    post "/api/password_resets", params: {
      password_reset: { phone: unique_phone }
    }, as: :json

    assert_response :created
    assert response.parsed_body["password_reset_id"].present?
    assert response.parsed_body["client_token"].present?
    assert response.parsed_body["whatsapp_url"].present?
    assert_nil OtpVerification.find(response.parsed_body["password_reset_id"]).user
  end

  test "rejects an invalid client token" do
    user = create_user(role: :student)
    StudentProfile.create!(user:, birth_date: Date.new(2008, 1, 1), parent_phone_e164: unique_phone)
    result = WhatsappVerifications::Request.call(phone: user.phone_e164, purpose: :password_reset, user:)

    post "/api/password_resets/#{result.verification.id}/status", params: {
      password_reset: { client_token: "wrong-token" }
    }, as: :json

    assert_response :unprocessable_entity
  end

  test "does not allow a reset link to be reused" do
    user = create_user(role: :parent)
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    result = WhatsappVerifications::Request.call(phone: user.phone_e164, purpose: :password_reset, user:)
    message = URI.decode_www_form(URI(result.whatsapp_url).query).to_h.fetch("text")
    WhatsappVerifications::Confirm.call(phone: user.phone_e164, message:)
    params = {
      password_reset: {
        client_token: result.client_token,
        password: "NewValidPassword123!",
        password_confirmation: "NewValidPassword123!"
      }
    }

    patch "/api/password_resets/#{result.verification.id}", params:, as: :json
    assert_response :no_content
    patch "/api/password_resets/#{result.verification.id}", params:, as: :json

    assert_response :unprocessable_entity
  end
end
