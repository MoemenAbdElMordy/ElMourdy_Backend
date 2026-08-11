require "test_helper"

class Api::TeacherControlControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_user(role: :teacher)
    @token = Sessions::Start.call(user: @teacher).raw_token
    @year, @grade, @branch, = create_curriculum
  end

  test "teacher lists manages and resets parent accounts" do
    student = create_student(parent_phone: "+201100000002")
    parent = create_parent(phone: "+201100000002")
    StudentParentLink.create!(
      student_profile: student, parent_profile: parent, relation: :father,
      status: :active, linked_at: Time.current
    )
    session = start_test_session(parent.user)

    get "/api/parents", headers: authorization_header(@token)
    assert_response :success
    assert_equal parent.user_id, response.parsed_body.dig("parents", 0, "id")

    patch "/api/parents/#{parent.user_id}", params: { parent: { status: "suspended" } },
      headers: authorization_header(@token), as: :json
    assert_response :success
    assert parent.user.reload.suspended?
    assert session.session.reload.revoked?

    patch "/api/parents/#{parent.user_id}/password", params: { parent: { password: "NewParentPassword123!" } },
      headers: authorization_header(@token), as: :json
    assert_response :no_content
    assert parent.user.reload.authenticate("NewParentPassword123!")
  end

  test "teacher previews a student and loads detailed reports" do
    student = create_student
    StudentEnrollment.create!(
      student_profile: student, academic_year: @year, grade: @grade,
      enrolled_at: Time.current, status: :active
    )

    get "/api/students/#{student.user_id}/preview", headers: authorization_header(@token)
    assert_response :success
    assert_equal student.user.name, response.parsed_body.dig("preview", "student", "name")
    assert_equal 1, response.parsed_body.dig("preview", "statistics", "subjects_count")

    get "/api/management_report", params: { academic_year_id: @year.id, grade_id: @grade.id },
      headers: authorization_header(@token)
    assert_response :success
    assert_equal 1, response.parsed_body.dig("report", "overview", "students_count")
    assert_equal student.user_id, response.parsed_body.dig("report", "students", 0, "id")
  end

  test "non teacher cannot manage parents or preview students" do
    parent = create_parent
    student = create_student
    token = Sessions::Start.call(user: parent.user).raw_token

    get "/api/parents", headers: authorization_header(token)
    assert_response :forbidden
    get "/api/students/#{student.user_id}/preview", headers: authorization_header(token)
    assert_response :forbidden
  end

  private

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
