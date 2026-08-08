require "test_helper"

class ActivationCodesRedeemTest < ActiveSupport::TestCase
  test "redeems a code and creates one lesson entitlement atomically" do
    student = create_student
    year, grade, _branch, _chapter, lesson = create_curriculum
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, status: :active, enrolled_at: Time.current)
    raw_code = "ELMOURDY-TEST-001"
    batch = ActivationCodeBatch.create!(
      lesson:,
      academic_year: year,
      grade:,
      name: "Test Batch",
      quantity: 1,
      expires_on: Date.current + 30.days
    )
    code = batch.activation_codes.create!(
      code_digest: Security::DigestValue.call(raw_code),
      status: :unused
    )

    grant = ActivationCodes::Redeem.call(raw_code:, student_profile: student)

    assert grant.active?
    assert_equal lesson, grant.lesson
    assert code.reload.redeemed?
    assert_equal student, code.redeemed_by_student_profile
  end

  test "does not allow the same code to be redeemed twice" do
    first_student = create_student
    second_student = create_student
    year, grade, _branch, _chapter, lesson = create_curriculum
    [ first_student, second_student ].each do |student|
      StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, status: :active, enrolled_at: Time.current)
    end
    raw_code = "ELMOURDY-TEST-002"
    batch = ActivationCodeBatch.create!(
      lesson:,
      academic_year: year,
      grade:,
      name: "Test Batch",
      quantity: 1,
      expires_on: Date.current + 30.days
    )
    batch.activation_codes.create!(code_digest: Security::DigestValue.call(raw_code), status: :unused)
    ActivationCodes::Redeem.call(raw_code:, student_profile: first_student)

    assert_raises(ApplicationService::Error) do
      ActivationCodes::Redeem.call(raw_code:, student_profile: second_student)
    end
  end
end
