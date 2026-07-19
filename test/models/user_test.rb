require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires an E.164 phone number" do
    user = User.new(
      role: :student,
      status: :active,
      name: "Student",
      phone_e164: "01000000000",
      password: "ValidPassword123!"
    )

    assert_not user.valid?
    assert_includes user.errors[:phone_e164], "must use E.164 format"
  end

  test "hashes passwords with BCrypt" do
    user = create_user

    assert user.authenticate("ValidPassword123!")
    assert_not_equal "ValidPassword123!", user.password_digest
  end
end
