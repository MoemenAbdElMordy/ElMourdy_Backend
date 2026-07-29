require "test_helper"

class OtpVerificationsRequestTest < ActiveSupport::TestCase
  class FakeMessenger
    attr_reader :phone, :code

    def send_otp(phone:, code:)
      @phone = phone
      @code = code
      "message-id"
    end
  end

  test "creates and delivers a verification code" do
    messenger = FakeMessenger.new

    result = OtpVerifications::Request.call(
      phone: "01012345678",
      purpose: :student_registration,
      messenger:
    )

    assert_equal "+201012345678", messenger.phone
    assert_match(/\A\d{6}\z/, messenger.code)
    assert_equal "message-id", result.message_id
    assert_equal "whatsapp", result.verification.metadata.fetch("channel")
    assert_equal "message-id", result.verification.metadata.fetch("message_id")
    assert_not_equal messenger.code, result.verification.code_digest
  end

  test "prevents immediate repeated requests" do
    messenger = FakeMessenger.new
    OtpVerifications::Request.call(
      phone: "01012345678",
      purpose: :student_registration,
      messenger:
    )

    error = assert_raises(ApplicationService::Error) do
      OtpVerifications::Request.call(
        phone: "01012345678",
        purpose: :student_registration,
        messenger:
      )
    end

    assert_equal "Please wait before requesting another code", error.message
  end
end
