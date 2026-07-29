require "test_helper"

class OtpVerificationsVerifyTest < ActiveSupport::TestCase
  test "verifies the correct code" do
    verification = create_verification(code: "483921")

    result = OtpVerifications::Verify.call(verification:, code: "483921")

    assert result.verified?
    assert result.verified_at.present?
    assert_equal 1, result.attempts_count
  end

  test "counts invalid attempts" do
    verification = create_verification(code: "483921")

    assert_raises(ApplicationService::Error) do
      OtpVerifications::Verify.call(verification:, code: "111111")
    end

    assert_equal 1, verification.reload.attempts_count
    assert verification.pending?
  end

  test "expires an old verification" do
    verification = create_verification(code: "483921", expires_at: 1.minute.from_now)

    assert_raises(ApplicationService::Error) do
      OtpVerifications::Verify.call(verification:, code: "483921", at: 2.minutes.from_now)
    end

    assert verification.reload.expired?
  end

  private

  def create_verification(code:, expires_at: 10.minutes.from_now)
    OtpVerification.create!(
      phone_e164: "+201012345678",
      purpose: :student_registration,
      code_digest: Security::DigestValue.call(code),
      expires_at:
    )
  end
end
