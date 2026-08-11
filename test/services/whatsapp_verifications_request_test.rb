require "test_helper"

class WhatsappVerificationsRequestTest < ActiveSupport::TestCase
  test "creates a single-use inbound verification link" do
    user = create_unverified_user

    result = WhatsappVerifications::Request.call(
      phone: user.phone_e164,
      purpose: :student_registration,
      user:
    )

    assert_equal "whatsapp_inbound", result.verification.metadata.fetch("channel")
    assert result.verification.metadata.fetch("client_token_digest").present?
    assert_not_equal result.client_token, result.verification.metadata.fetch("client_token_digest")
    assert_match(%r{\Ahttps://wa\.me/201069229786\?text=VERIFY\+?[A-F0-9%]+\z}, result.whatsapp_url)
  end

  private

  def create_unverified_user
    User.create!(
      role: :student,
      status: :active,
      name: "Pending Student",
      phone_e164: unique_phone,
      password: "ValidPassword123!",
      password_confirmation: "ValidPassword123!"
    )
  end
end
