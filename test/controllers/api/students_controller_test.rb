require "test_helper"

class Api::StudentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_user(role: :teacher)
    @token = Sessions::Start.call(user: @teacher).raw_token
    @year, @grade = create_academic_setup
  end

  test "searches and filters real students" do
    matching = enrolled_student(name: "Target Student")
    enrolled_student(name: "Different Student")

    get "/api/students", params: { query: "Target", grade_id: @grade.id },
      headers: authorization_header(@token)

    assert_response :success
    assert_equal [ matching.user_id ], response.parsed_body["students"].pluck("id")
    assert_equal matching.center_name, response.parsed_body.dig("students", 0, "center_name")
  end

  test "paginates students and returns navigation metadata" do
    3.times { |index| enrolled_student(name: "Paged Student #{index}") }

    get "/api/students", params: { page: 2, per_page: 2 }, headers: authorization_header(@token)

    assert_response :success
    assert_equal 1, response.parsed_body.fetch("students").length
    assert_equal 3, response.parsed_body.dig("pagination", "total_count")
    assert_equal 2, response.parsed_body.dig("pagination", "total_pages")
    assert_equal 1, response.parsed_body.dig("pagination", "previous_page")
    assert_nil response.parsed_body.dig("pagination", "next_page")
  end

  test "returns student details and suspends the account" do
    student = enrolled_student(name: "Managed Student")

    get "/api/students/#{student.user_id}", headers: authorization_header(@token)
    assert_response :success
    assert_equal @grade.name, response.parsed_body.dig("student", "grade")
    assert_equal student.center_name, response.parsed_body.dig("student", "center_name")

    patch "/api/students/#{student.user_id}", params: { student: { status: "suspended" } },
      headers: authorization_header(@token), as: :json

    assert_response :success
    assert student.user.reload.suspended?
  end

  test "searches students by email address" do
    matching = enrolled_student(name: "Email Match")
    matching.user.update!(email: "unique.student.search@example.test")
    other = enrolled_student(name: "Other Student")
    other.user.update!(email: "other.student@example.test")

    get "/api/students", params: { query: "student.search@" }, headers: authorization_header(@token)

    assert_response :success
    assert_equal [ matching.user_id ], response.parsed_body.fetch("students").pluck("id")
    assert_equal "unique.student.search@example.test", response.parsed_body.dig("students", 0, "email")
  end

  test "returns watched and unwatched video progress for the enrolled curriculum" do
    student = enrolled_student(name: "Progress Student")
    branch = Branch.create!(academic_year: @year, grade: @grade, title: "Grammar", position: 1, status: :published)
    chapter = branch.chapters.create!(title: "Chapter One", position: 1, status: :published)
    lesson = chapter.lessons.create!(title: "Lesson One", position: 1, status: :published)
    watched = lesson.lectures.create!(title: "Watched Video", position: 1, status: :published,
      video_source_type: :youtube, youtube_video_id: "abcdefghijk", duration_seconds: 100)
    lesson.lectures.create!(title: "Unwatched Video", position: 2, status: :published,
      video_source_type: :youtube, youtube_video_id: "lmnopqrstuv", duration_seconds: 200)
    student.lecture_watch_events.create!(lecture: watched, started_at: 10.minutes.ago,
      watched_seconds: 40, last_position_seconds: 50)

    get "/api/students/#{student.user_id}", headers: authorization_header(@token)

    assert_response :success
    progress = response.parsed_body.dig("student", "video_progress")
    assert_equal [ "Watched Video", "Unwatched Video" ], progress.pluck("title")
    assert_equal 40, progress.first["progress_percent"]
    assert progress.first["watched"]
    assert_not progress.second["watched"]
  end

  test "returns complete account, homework, exam, and attempt reporting" do
    student = enrolled_student(name: "Reported Student")
    student.user.update!(email: "reported.student@example.test")
    homework = create_assessment(title: "Assigned Homework", type: :homework)
    exam = create_assessment(title: "Assigned Exam", type: :exam)
    attempt = student.exam_attempts.create!(
      exam: homework, attempt_number: 1, status: :submitted, started_at: 20.minutes.ago,
      submitted_at: 10.minutes.ago, score_points: 1, max_points: 1, percent: 100, result_status: :passed
    )

    get "/api/students/#{student.user_id}", headers: authorization_header(@token)

    assert_response :success
    payload = response.parsed_body.fetch("student")
    assert payload["account_verified"]
    assert_equal 0, payload["active_sessions_count"]
    assert_equal [ homework.id, exam.id ].sort, payload.fetch("assessments").pluck("id").sort
    homework_report = payload.fetch("assessments").find { |item| item["id"] == homework.id }
    assert_equal "submitted", homework_report["status"]
    assert_equal 100.0, homework_report["best_percent"]
    assert_equal "homework", payload.fetch("attempts").find { |item| item["id"] == attempt.id }["assessment_type"]
  end

  test "changes enrollment and resets password while ending active sessions" do
    student = enrolled_student(name: "Transferred Student")
    next_year = AcademicYear.create!(
      name: "2028/2029", starts_on: Date.new(2028, 9, 1), ends_on: Date.new(2029, 8, 31), status: :draft
    )
    next_grade = Grade.find_or_create_by!(level: 2) { |grade| grade.name = "Second Secondary" }
    session = start_test_session(student.user)

    patch "/api/students/#{student.user_id}/enrollment", params: {
      enrollment: { academic_year_id: next_year.id, grade_id: next_grade.id }
    }, headers: authorization_header(@token), as: :json
    assert_response :success
    assert_equal next_year.id, response.parsed_body.dig("student", "academic_year_id")

    patch "/api/students/#{student.user_id}/password", params: { student: { password: "NewPassword123!" } },
      headers: authorization_header(@token), as: :json
    assert_response :no_content
    assert student.user.reload.authenticate("NewPassword123!")
    assert session.session.reload.revoked?
  end

  test "teacher changes the parent phone and removes a student device" do
    student = enrolled_student(name: "Controlled Student")
    device_session = start_test_session(student.user)
    device = device_session.session.device_registration

    patch "/api/students/#{student.user_id}/parent_phone", params: {
      parent_phone: { phone: "01100000002" }
    }, headers: authorization_header(@token), as: :json
    assert_response :success
    assert_equal "+201100000002", student.reload.parent_phone_e164

    delete "/api/students/#{student.user_id}/devices/#{device.id}",
      headers: authorization_header(@token), as: :json
    assert_response :no_content
    assert device.reload.removed?
    assert device_session.session.reload.revoked?
  end

  test "parent phone cannot match the student phone" do
    student = enrolled_student(name: "Protected Student")

    patch "/api/students/#{student.user_id}/parent_phone", params: {
      parent_phone: { phone: student.user.phone_e164 }
    }, headers: authorization_header(@token), as: :json

    assert_response :unprocessable_entity
    assert_equal "invalid_parent_phone", response.parsed_body.dig("error", "code")
  end

  private

  def enrolled_student(name:)
    profile = create_student
    profile.user.update!(name:)
    StudentEnrollment.create!(
      student_profile: profile,
      academic_year: @year,
      grade: @grade,
      enrolled_at: Time.current,
      status: :active
    )
    profile
  end

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_assessment(title:, type:)
    exam = Exam.create!(
      title:, assessment_type: type, scope_type: :comprehensive, academic_year: @year, grade: @grade,
      duration_minutes: 30, max_attempts: 3, pass_percent: 50, risk_from_percent: 50,
      risk_to_percent: 60, status: :published
    )
    question = exam.exam_questions.create!(body: "Question", points: 1, position: 1)
    question.exam_choices.create!(body: "Correct", is_correct: true, position: 1)
    question.exam_choices.create!(body: "Incorrect", is_correct: false, position: 2)
    exam
  end
end
