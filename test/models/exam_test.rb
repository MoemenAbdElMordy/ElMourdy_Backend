require "test_helper"

class ExamTest < ActiveSupport::TestCase
  test "accepts a comprehensive exam for one year and grade" do
    year, grade, = create_curriculum
    exam = Exam.new(
      title: "Comprehensive Exam",
      scope_type: :comprehensive,
      academic_year: year,
      grade:,
      duration_minutes: 120,
      max_attempts: 3,
      pass_percent: 50,
      risk_from_percent: 50,
      risk_to_percent: 60
    )

    assert exam.valid?
  end

  test "rejects scope references that do not match the scope type" do
    year, grade, branch, chapter, lesson = create_curriculum
    exam = Exam.new(
      title: "Invalid Exam",
      scope_type: :lesson,
      lesson:,
      chapter:,
      branch:,
      academic_year: year,
      grade:,
      duration_minutes: 30,
      max_attempts: 3,
      pass_percent: 50,
      risk_from_percent: 50,
      risk_to_percent: 60
    )

    assert_not exam.valid?
    assert_includes exam.errors[:scope_type], "does not match the supplied scope reference"
  end
end
