require "test_helper"

class Api::ExamsControllerTest < ActionDispatch::IntegrationTest
  test "teacher creates a complete published exam" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    year, grade, _branch, _chapter, lesson = create_curriculum

    post "/api/exams", params: { exam: exam_payload(year, grade, lesson) }, headers: auth(token), as: :json

    assert_response :created
    assert_equal "published", response.parsed_body.dig("exam", "status")
    assert_equal 1, response.parsed_body.dig("exam", "questions").size
    assert_equal 2, ExamChoice.count
  end

  test "student only sees published exams for the active enrollment" do
    exam = create_exam
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: exam.academic_year, grade: exam.grade, status: :active, enrolled_at: Time.current)
    token = start_test_session(student.user).raw_token

    get "/api/exams", headers: auth(token)

    assert_response :success
    assert_equal [ exam.id ], response.parsed_body.fetch("exams").pluck("id")
  end

  private

  def exam_payload(year, grade, lesson)
    {
      title: "Grammar Check", scope_type: "lesson", lesson_id: lesson.id,
      academic_year_id: year.id, grade_id: grade.id, duration_minutes: 15,
      max_attempts: 2, pass_percent: 60, risk_from_percent: 50, risk_to_percent: 59,
      status: "published", questions: [ {
        body: "Choose the correct answer", explanation: "The first choice is correct", points: 2,
        choices: [ { body: "First", is_correct: true }, { body: "Second", is_correct: false } ]
      } ]
    }
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
