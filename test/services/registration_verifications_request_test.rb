require "test_helper"

class RegistrationVerificationsRequestTest < ActiveSupport::TestCase
  test "sends a registration code through Telegram when configured" do
    user = create_student.user
    sent = []
    gateway = Object.new
    gateway.define_singleton_method(:send_code) do |**attributes|
      sent << attributes
      "telegram-request-123"
    end

    with_env("TELEGRAM_GATEWAY_ENABLED", "true") do
      with_env("TELEGRAM_GATEWAY_TOKEN", "test-token") do
        with_gateway(gateway) do
          result = RegistrationVerifications::Request.call(user:, purpose: :student_registration, channel: "telegram")
          assert_equal "telegram", result.verification.metadata["channel"]
          assert_equal "telegram-request-123", result.verification.metadata["gateway_request_id"]
          assert_equal user.phone_e164, sent.first[:phone]
          assert_match(/\A\d{6}\z/, sent.first[:code])
          assert_equal 600, sent.first[:ttl]
        end
      end
    end
  end

  test "does not offer Telegram while the account is unfunded" do
    user = create_student.user

    with_env("TELEGRAM_GATEWAY_ENABLED", nil) do
      with_env("TELEGRAM_GATEWAY_TOKEN", "test-token") do
        assert_not TelegramGateway.enabled?
        assert_raises(ApplicationService::Error) do
          RegistrationVerifications::Request.call(user:, purpose: :student_registration, channel: "telegram")
        end
        assert_equal 0, user.otp_verifications.count
      end
    end
  end

  test "defaults to email even when Telegram is configured" do
    user = create_student.user
    user.update!(email: "fallback@example.test")

    with_env("TELEGRAM_GATEWAY_TOKEN", "test-token") do
      result = RegistrationVerifications::Request.call(user:, purpose: :student_registration)
      assert_equal "email", result.verification.metadata["channel"]
      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_equal 1, user.otp_verifications.pending.count
    end
  end

  private

  def with_gateway(gateway)
    singleton = TelegramGateway::Client.singleton_class
    singleton.alias_method :original_new_for_test, :new
    singleton.define_method(:new) { gateway }
    yield
  ensure
    singleton.alias_method :new, :original_new_for_test
    singleton.remove_method :original_new_for_test
  end

  def with_env(key, value)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    previous.nil? ? ENV.delete(key) : ENV[key] = previous
  end
end
