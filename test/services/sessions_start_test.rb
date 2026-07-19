require "test_helper"

class SessionsStartTest < ActiveSupport::TestCase
  test "revokes the previous student session" do
    student = create_student
    first_device = Devices::Register.call(student_profile: student, fingerprint: "first-device")
    second_device = Devices::Register.call(student_profile: student, fingerprint: "second-device")
    first = Sessions::Start.call(user: student.user, device_registration: first_device)

    second = Sessions::Start.call(user: student.user, device_registration: second_device)

    assert first.session.reload.revoked?
    assert second.session.active?
    assert_equal 1, student.user.user_sessions.active.count
    assert_not_equal second.raw_token, second.session.session_token_digest
  end
end
