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
    assert_not user.authenticate("ValidPassword123!")
    assert active_session.session.reload.ended?
    assert OtpVerification.find(reset.fetch("password_reset_id")).consumed?

    post "/api/session", params: { session: { phone: user.phone_e164, password: "ValidPassword123!" } }, as: :json
    assert_response :unauthorized
    post "/api/session", params: { session: { phone: user.phone_e164, password: "NewValidPassword123!" } }, as: :json
    assert_response :created
  end

  test "rejects an email that does not belong to an active account" do
    post "/api/password_resets", params: { password_reset: { email: "missing@example.test" } }, as: :json
    assert_response :unprocessable_entity
    assert_empty ActionMailer::Base.deliveries
  end

  test "an unverified account can recover its password and then sign in for activation" do
    user = create_user(role: :parent).tap do |record|
      record.update!(email: "unverified.parent@example.test", phone_verified_at: nil)
    end
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)

    post "/api/password_resets", params: { password_reset: { email: user.email } }, as: :json
    assert_response :created
    reset = response.parsed_body

    post "/api/password_resets/#{reset.fetch('password_reset_id')}/verify", params: {
      password_reset: { client_token: reset.fetch("client_token"), code: delivered_code }
    }, as: :json
    assert_response :success

    patch "/api/password_resets/#{reset.fetch('password_reset_id')}", params: {
      password_reset: { client_token: reset.fetch("client_token"), password: "NewValidPassword123!", password_confirmation: "NewValidPassword123!" }
    }, as: :json
    assert_response :no_content

    post "/api/session", params: { session: { phone: user.phone_e164, password: "NewValidPassword123!" } }, as: :json
    assert_response :created
    assert_equal false, response.parsed_body.dig("user", "verified")
  end

  test "an expired verified code remains expired and cannot change the password" do
    user = create_user(role: :parent).tap { |record| record.update!(email: "expired.reset@example.test") }
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    result = EmailVerifications::Request.call(user:, purpose: :password_reset)
    OtpVerifications::Verify.call(verification: result.verification, code: delivered_code)
    travel_to(result.verification.expires_at + 1.second) do
      patch "/api/password_resets/#{result.verification.id}", params: {
        password_reset: { client_token: result.client_token, password: "NewValidPassword123!", password_confirmation: "NewValidPassword123!" }
      }, as: :json
    end

    assert_response :unprocessable_entity
    assert result.verification.reload.expired?
    assert user.reload.authenticate("ValidPassword123!")
  end

  test "teacher and assistant can sign in with the new password after recovery" do
    %i[teacher assistant].each do |role|
      user = create_user(role:).tap { |record| record.update!(email: "reset.#{role}@example.test") }
      AssistantProfile.create!(user:, title: "Support", can_login: true) if role == :assistant
      result = EmailVerifications::Request.call(user:, purpose: :password_reset)
      OtpVerifications::Verify.call(verification: result.verification, code: delivered_code)

      patch "/api/password_resets/#{result.verification.id}", params: {
        password_reset: { client_token: result.client_token, password: "NewValidPassword123!", password_confirmation: "NewValidPassword123!" }
      }, as: :json
      assert_response :no_content

      post "/api/session", params: { session: { phone: user.phone_e164, password: "NewValidPassword123!" } }, as: :json
      assert_response :created
      assert_equal role.to_s, response.parsed_body.dig("user", "role")
    end
  end

  test "missing or unconfirmed new password never reports a successful reset" do
    user = create_user(role: :parent).tap { |record| record.update!(email: "invalid.reset@example.test") }
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    result = EmailVerifications::Request.call(user:, purpose: :password_reset)
    OtpVerifications::Verify.call(verification: result.verification, code: delivered_code)

    [ nil, "NewValidPassword123!" ].each do |password|
      patch "/api/password_resets/#{result.verification.id}", params: {
        password_reset: { client_token: result.client_token, password: }
      }, as: :json
      assert_response :unprocessable_entity
      assert result.verification.reload.verified?
      assert user.reload.authenticate("ValidPassword123!")
    end
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

  test "resending a code invalidates an older verified reset" do
    user = create_user(role: :parent).tap { |record| record.update!(email: "resend.reset@example.test") }
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    first = EmailVerifications::Request.call(user:, purpose: :password_reset)
    OtpVerifications::Verify.call(verification: first.verification, code: delivered_code)

    travel 61.seconds do
      second = EmailVerifications::Request.call(user:, purpose: :password_reset)
      assert first.verification.reload.expired?
      assert second.verification.reload.pending?
    end

    patch "/api/password_resets/#{first.verification.id}", params: {
      password_reset: { client_token: first.client_token, password: "NewValidPassword123!", password_confirmation: "NewValidPassword123!" }
    }, as: :json
    assert_response :unprocessable_entity
    assert user.reload.authenticate("ValidPassword123!")
  end

  test "failed email delivery preserves the previous code and permits an immediate retry" do
    user = create_user(role: :parent).tap { |record| record.update!(email: "delivery.reset@example.test") }
    ParentProfile.create!(user:, verified_parent_phone_e164: user.phone_e164)
    first = EmailVerifications::Request.call(user:, purpose: :password_reset)

    travel 61.seconds do
      original_with = VerificationMailer.method(:with)
      VerificationMailer.define_singleton_method(:with) { |**| raise IOError, "SMTP unavailable" }
      begin
        assert_raises(ApplicationService::Error) do
          EmailVerifications::Request.call(user:, purpose: :password_reset)
        end
      ensure
        VerificationMailer.define_singleton_method(:with, original_with)
      end
      assert first.verification.reload.pending?
      retry_request = EmailVerifications::Request.call(user:, purpose: :password_reset)
      assert retry_request.verification.pending?
      assert first.verification.reload.expired?
    end
  end

  private

  def delivered_code
    ActionMailer::Base.deliveries.last.text_part.body.decoded.match(/\d{6}/).to_s
  end
end
