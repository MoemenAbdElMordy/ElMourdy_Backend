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
