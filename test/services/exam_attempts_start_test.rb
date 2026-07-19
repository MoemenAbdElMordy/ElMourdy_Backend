require "test_helper"

class ExamAttemptsStartTest < ActiveSupport::TestCase
  test "allocates sequential attempt numbers" do
    student = create_student
    exam = create_exam

    first = ExamAttempts::Start.call(exam:, student_profile: student)
    second = ExamAttempts::Start.call(exam:, student_profile: student)

    assert_equal 1, first.attempt_number
    assert_equal 2, second.attempt_number
    assert_equal exam.exam_questions.order(:position).pluck(:id), first.question_order
  end

  test "enforces the configured maximum attempts" do
    student = create_student
    exam = create_exam
    exam.update!(max_attempts: 1)
    ExamAttempts::Start.call(exam:, student_profile: student)

    assert_raises(ApplicationService::Error) do
      ExamAttempts::Start.call(exam:, student_profile: student)
    end
  end
end
