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

    patch "/api/students/#{student.user_id}", params: { student: { status: "suspended" } },
      headers: authorization_header(@token), as: :json

    assert_response :success
    assert student.user.reload.suspended?
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
end
