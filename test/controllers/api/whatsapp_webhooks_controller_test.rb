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
end
