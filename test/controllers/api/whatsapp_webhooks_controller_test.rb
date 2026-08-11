require "test_helper"

class Api::WhatsappWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_verify_token = ENV["WHATSAPP_WEBHOOK_VERIFY_TOKEN"]
    @original_app_secret = ENV["META_APP_SECRET"]
    ENV["WHATSAPP_WEBHOOK_VERIFY_TOKEN"] = "test-verify-token"
    ENV["META_APP_SECRET"] = "test-app-secret"
  end

  teardown do
    ENV["WHATSAPP_WEBHOOK_VERIFY_TOKEN"] = @original_verify_token
    ENV["META_APP_SECRET"] = @original_app_secret
  end

  test "answers a valid subscription challenge" do
    get api_webhooks_whatsapp_url, params: {
      "hub.mode" => "subscribe",
      "hub.verify_token" => "test-verify-token",
      "hub.challenge" => "challenge-value"
    }

    assert_response :success
    assert_equal "challenge-value", response.body
  end

  test "rejects an invalid subscription token" do
    get api_webhooks_whatsapp_url, params: {
      "hub.mode" => "subscribe",
      "hub.verify_token" => "wrong-token",
      "hub.challenge" => "challenge-value"
    }

    assert_response :forbidden
  end

  test "accepts a correctly signed webhook payload" do
    payload = { object: "whatsapp_business_account", entry: [] }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", "test-app-secret", payload)

    post api_webhooks_whatsapp_url,
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => "sha256=#{signature}"
      }

    assert_response :no_content
  end

  test "confirms a registration from a matching inbound WhatsApp message" do
    user = User.create!(
      role: :student,
      status: :active,
      name: "Pending Student",
      phone_e164: "+201000000001",
      password: "ValidPassword123!",
      password_confirmation: "ValidPassword123!"
    )
    result = WhatsappVerifications::Request.call(
      phone: user.phone_e164,
      purpose: :student_registration,
      user:
    )
    message = URI.decode_www_form(URI(result.whatsapp_url).query).to_h.fetch("text")
    payload = inbound_message_payload(from: "201000000001", message:).to_json

    post api_webhooks_whatsapp_url,
      params: payload,
      headers: signed_headers(payload)

    assert_response :no_content
    assert result.verification.reload.verified?
    assert user.reload.phone_verified_at.present?
  end

  test "ignores a verification message from a different phone" do
    user = User.create!(
      role: :student,
      status: :active,
      name: "Pending Student",
      phone_e164: "+201000000001",
      password: "ValidPassword123!",
      password_confirmation: "ValidPassword123!"
    )
    result = WhatsappVerifications::Request.call(
      phone: user.phone_e164,
      purpose: :student_registration,
      user:
    )
    message = URI.decode_www_form(URI(result.whatsapp_url).query).to_h.fetch("text")
    payload = inbound_message_payload(from: "201200000003", message:).to_json

    post api_webhooks_whatsapp_url,
      params: payload,
      headers: signed_headers(payload)

    assert_response :no_content
    assert result.verification.reload.pending?
    assert_nil user.reload.phone_verified_at
  end

  private

  def signed_headers(payload)
    signature = OpenSSL::HMAC.hexdigest("SHA256", "test-app-secret", payload)
    {
      "Content-Type" => "application/json",
      "X-Hub-Signature-256" => "sha256=#{signature}"
    }
  end

  def inbound_message_payload(from:, message:)
    {
      object: "whatsapp_business_account",
      entry: [
        {
          changes: [
            {
              field: "messages",
              value: {
                messages: [
                  {
                    from:,
                    id: "wamid.test-message",
                    timestamp: Time.current.to_i.to_s,
                    type: "text",
                    text: { body: message }
                  }
                ]
              }
            }
          ]
        }
      ]
    }
  end
end
