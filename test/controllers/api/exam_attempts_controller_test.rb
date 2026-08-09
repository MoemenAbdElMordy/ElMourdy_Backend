require "test_helper"

class Api::ExamAttemptsControllerTest < ActionDispatch::IntegrationTest
  test "student completes an exam and receives automatic grading" do
    exam = create_exam
    student = enrolled_student(exam)
    token = start_test_session(student.user).raw_token

    post "/api/exams/#{exam.id}/attempts", headers: auth(token), as: :json
    assert_response :created
    attempt_id = response.parsed_body.dig("attempt", "id")
    answers = exam.exam_questions.map do |question|
      { question_id: question.id, choice_id: question.exam_choices.find_by!(is_correct: true).id }
    end

    post "/api/exam_attempts/#{attempt_id}/submit", params: { answers: }, headers: auth(token), as: :json

    assert_response :success
    assert_equal "passed", response.parsed_body.dig("attempt", "result_status")
    assert_equal "100.0", response.parsed_body.dig("attempt", "percent")
    assert response.parsed_body.dig("attempt", "questions", 0, "correct_choice_id").present?
  end

  test "parent can read a linked student's result but cannot start an attempt" do
    exam = create_exam
    student = enrolled_student(exam)
    attempt = ExamAttempts::Start.call(exam:, student_profile: student)
    answers = exam.exam_questions.map { |question| { question_id: question.id, choice_id: question.exam_choices.first.id } }
    ExamAttempts::Submit.call(attempt:, answers:)
    parent = create_parent
    StudentParentLink.create!(student_profile: student, parent_profile: parent, relation: :father, status: :active, linked_at: Time.current)
    token = Sessions::Start.call(user: parent.user).raw_token

    get "/api/exam_attempts/#{attempt.id}", headers: auth(token)
    assert_response :success

    post "/api/exams/#{exam.id}/attempts", headers: auth(token), as: :json
    assert_response :forbidden
  end

  private

  def enrolled_student(exam)
    create_student.tap do |student|
      StudentEnrollment.create!(student_profile: student, academic_year: exam.academic_year, grade: exam.grade, status: :active, enrolled_at: Time.current)
    end
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
