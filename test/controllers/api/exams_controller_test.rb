require "test_helper"

class Api::ExamsControllerTest < ActionDispatch::IntegrationTest
  test "homework progress includes students who did not start" do
    homework = create_exam
    homework.update!(assessment_type: :homework)
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: homework.academic_year,
      grade: homework.grade, status: :active, enrolled_at: Time.current)
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token

    get "/api/exams/#{homework.id}/progress", headers: auth(token)

    assert_response :success
    item = response.parsed_body.fetch("students").sole
    assert_equal student.user_id, item.fetch("student_id")
    assert_equal "not_started", item.fetch("status")
    assert_equal 0, item.fetch("attempts_count")
  end

  test "progress searches all pages by student phone and center" do
    exam = create_exam
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    matching = create_student
    matching.update!(center_name: "Future Academy")
    matching.user.update!(name: "Matched Student")
    other = create_student
    [matching, other].each do |profile|
      StudentEnrollment.create!(student_profile: profile, academic_year: exam.academic_year,
        grade: exam.grade, status: :active, enrolled_at: Time.current)
    end

    get "/api/exams/#{exam.id}/progress", params: { query: "Future" }, headers: auth(token)
    assert_response :success
    assert_equal [matching.user_id], response.parsed_body.fetch("students").pluck("student_id")
    assert_equal "Future Academy", response.parsed_body.dig("students", 0, "center_name")

    get "/api/exams/#{exam.id}/progress", params: { query: matching.user.phone_e164 }, headers: auth(token)
    assert_response :success
    assert_equal [matching.user_id], response.parsed_body.fetch("students").pluck("student_id")
  end

  test "progress filters unstarted pending submitted passed and not passed students" do
    exam = create_exam
    profiles = 4.times.map { create_student }
    profiles.each do |profile|
      StudentEnrollment.create!(student_profile: profile, academic_year: exam.academic_year,
        grade: exam.grade, status: :active, enrolled_at: Time.current)
    end
    profiles[1].exam_attempts.create!(exam:, attempt_number: 1, status: :in_progress, started_at: Time.current)
    [ [2, :passed, 100], [3, :failed, 0] ].each do |index, result, percent|
      profiles[index].exam_attempts.create!(exam:, attempt_number: 1, status: :submitted,
        started_at: 10.minutes.ago, submitted_at: Time.current, score_points: percent == 100 ? 2 : 0,
        max_points: 2, percent:, result_status: result)
    end
    teacher = create_user(role: :teacher)
    headers = auth(Sessions::Start.call(user: teacher).raw_token)
    expected = {
      "not_started" => [profiles[0].user_id], "in_progress" => [profiles[1].user_id],
      "submitted" => [profiles[2].user_id, profiles[3].user_id],
      "passed" => [profiles[2].user_id], "not_passed" => [profiles[3].user_id]
    }
    expected.each do |filter, user_ids|
      get "/api/exams/#{exam.id}/progress", params: { progress_status: filter }, headers: headers
      assert_response :success
      assert_equal user_ids.sort, response.parsed_body.fetch("students").pluck("student_id").sort
      assert_equal user_ids.length, response.parsed_body.dig("pagination", "total_count")
    end
  end

  test "homework progress requires homework permission" do
    homework = create_exam
    homework.update!(assessment_type: :homework)
    assistant = create_user(role: :assistant)
    profile = AssistantProfile.create!(user: assistant)
    token = Sessions::Start.call(user: assistant).raw_token

    get "/api/exams/#{homework.id}/progress", headers: auth(token)
    assert_response :forbidden

    profile.assistant_permissions.create!(permission_key: "manage_homeworks", enabled: true)
    get "/api/exams/#{homework.id}/progress", headers: auth(token)
    assert_response :success
  end

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

  test "exam grade must match its selected lesson" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    year, grade, _branch, _chapter, lesson = create_curriculum
    other_grade = Grade.find_or_create_by!(level: 2) { |record| record.name = "Second Secondary" }
    payload = exam_payload(year, grade, lesson).merge(grade_id: other_grade.id)

    post "/api/exams", params: { exam: payload }, headers: auth(token), as: :json

    assert_response :unprocessable_entity
  end

  test "teacher can create a grade-wide exam without selecting a lesson" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    year, grade, _branch, _chapter, lesson = create_curriculum
    payload = exam_payload(year, grade, lesson).merge(scope_type: "comprehensive", lesson_id: nil)

    post "/api/exams", params: { exam: payload }, headers: auth(token), as: :json

    assert_response :created
    assert_equal "comprehensive", response.parsed_body.dig("exam", "scope_type")
    assert_nil response.parsed_body.dig("exam", "lesson_id")
  end

  test "assistant homework permission is independent from exam permission" do
    homework = create_exam
    homework.update!(assessment_type: :homework)
    assistant = create_user(role: :assistant)
    profile = AssistantProfile.create!(user: assistant)
    profile.assistant_permissions.create!(permission_key: "manage_homeworks", enabled: true)
    token = Sessions::Start.call(user: assistant).raw_token

    get "/api/exams", params: { assessment_type: "homework" }, headers: auth(token)
    assert_response :success
    assert_equal [ homework.id ], response.parsed_body.fetch("exams").pluck("id")

    get "/api/exams", params: { assessment_type: "exam" }, headers: auth(token)
    assert_response :forbidden
  end

  test "teacher can replace questions before attempts begin" do
    exam = create_exam
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    payload = exam_payload(exam.academic_year, exam.grade, exam.lesson)
    payload[:title] = "Updated homework"
    payload[:assessment_type] = "homework"

    patch "/api/exams/#{exam.id}", params: { exam: payload }, headers: auth(token), as: :json

    assert_response :success
    assert_equal "Updated homework", exam.reload.title
    assert_equal 1, exam.exam_questions.count
    assert_equal 2, exam.exam_questions.first.exam_choices.count
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
