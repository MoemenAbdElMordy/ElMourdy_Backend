require "test_helper"

class DevicesRegisterTest < ActiveSupport::TestCase
  test "allows at most three active devices" do
    student = create_student
    3.times do |index|
      Devices::Register.call(student_profile: student, fingerprint: "device-#{index}")
    end

    assert_raises(ApplicationService::Error) do
      Devices::Register.call(student_profile: student, fingerprint: "device-4")
    end
    assert_equal 3, student.device_registrations.active.count
  end

  test "returns the existing device for the same fingerprint" do
    student = create_student
    original = Devices::Register.call(student_profile: student, fingerprint: "same-device")

    repeated = Devices::Register.call(student_profile: student, fingerprint: "same-device")

    assert_equal original.id, repeated.id
    assert_equal 1, student.device_registrations.count
  end
end
