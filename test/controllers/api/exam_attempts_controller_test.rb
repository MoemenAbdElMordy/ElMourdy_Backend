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

  test "homework can correct the first answer immediately and locks the question" do
    exam = create_exam
    exam.update!(assessment_type: :homework, correct_after_each_answer: true)
    student = enrolled_student(exam)
    token = start_test_session(student.user).raw_token
    post "/api/exams/#{exam.id}/attempts", headers: auth(token), as: :json
    attempt_id = response.parsed_body.dig("attempt", "id")
    question = exam.exam_questions.first
    choice = question.exam_choices.find_by!(is_correct: true)

    post "/api/exam_attempts/#{attempt_id}/answer", params: { question_id: question.id, choice_id: choice.id }, headers: auth(token), as: :json
    assert_response :success
    assert_equal true, response.parsed_body.dig("answer", "is_correct")
    assert_equal choice.id, response.parsed_body.dig("answer", "correct_choice_id")

    post "/api/exam_attempts/#{attempt_id}/answer", params: { question_id: question.id, choice_id: choice.id }, headers: auth(token), as: :json
    assert_response :unprocessable_entity
  end

  test "homework result hides answer details when configured" do
    exam = create_exam
    exam.update!(assessment_type: :homework, show_answers_after_submission: false)
    student = enrolled_student(exam)
    token = start_test_session(student.user).raw_token
    post "/api/exams/#{exam.id}/attempts", headers: auth(token), as: :json
    attempt_id = response.parsed_body.dig("attempt", "id")
    answers = exam.exam_questions.map { |question| { question_id: question.id, choice_id: question.exam_choices.find_by!(is_correct: true).id } }

    post "/api/exam_attempts/#{attempt_id}/submit", params: { answers: }, headers: auth(token), as: :json

    assert_response :success
    assert_nil response.parsed_body.dig("attempt", "questions", 0, "correct_choice_id")
    assert_nil response.parsed_body.dig("attempt", "questions", 0, "is_correct")
  end

  test "student in an assigned secondary grade can start a multi-grade homework" do
    homework = create_exam
    homework.update!(assessment_type: :homework)
    other_grade = Grade.find_or_create_by!(level: 3) { |grade| grade.name = "Third Secondary" }
    homework.exam_grade_assignments.create!(grade: homework.grade)
    homework.exam_grade_assignments.create!(grade: other_grade)
    student = create_student
    StudentEnrollment.create!(
      student_profile: student,
      academic_year: homework.academic_year,
      grade: other_grade,
      status: :active,
      enrolled_at: Time.current
    )
    token = start_test_session(student.user).raw_token

    post "/api/exams/#{homework.id}/attempts", headers: auth(token), as: :json

    assert_response :created
    assert_equal homework.id, response.parsed_body.dig("attempt", "exam_id")
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
