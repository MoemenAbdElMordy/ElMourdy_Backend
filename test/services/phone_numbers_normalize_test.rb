require "test_helper"

class PhoneNumbersNormalizeTest < ActiveSupport::TestCase
  test "normalizes local and international Egyptian mobile numbers" do
    assert_equal "+201012345678", PhoneNumbers::Normalize.call("01012345678")
    assert_equal "+201012345678", PhoneNumbers::Normalize.call("201012345678")
    assert_equal "+201012345678", PhoneNumbers::Normalize.call("+20 10 1234 5678")
  end

  test "rejects invalid phone numbers" do
    assert_raises(ApplicationService::Error) { PhoneNumbers::Normalize.call("123") }
  end
end
