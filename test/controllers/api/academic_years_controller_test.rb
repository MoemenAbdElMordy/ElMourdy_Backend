require "test_helper"

class Api::AcademicYearsControllerTest < ActionDispatch::IntegrationTest
  test "teacher creates and activates an academic year" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    previous_year, = create_academic_setup

    post "/api/academic_years", params: {
      academic_year: {
        name: "2027/2028",
        starts_on: "2027-09-01",
        ends_on: "2028-08-31",
        status: "active"
      }
    }, headers: authorization_header(token), as: :json

    assert_response :created
    assert_equal "active", response.parsed_body.dig("academic_year", "status")
    assert previous_year.reload.archived?
    assert_equal 1, AcademicYear.active.count
  end

  test "assistant needs the academic year permission" do
    assistant = create_user(role: :assistant)
    AssistantProfile.create!(user: assistant)
    token = Sessions::Start.call(user: assistant).raw_token

    get "/api/academic_years", headers: authorization_header(token)

    assert_response :forbidden
  end

  test "copies curriculum structure and rolls students into the next grade" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    source, grade, = create_curriculum
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: source, grade:, enrolled_at: Time.current)
    target = AcademicYear.create!(
      name: "2029/2030", starts_on: Date.new(2029, 9, 1), ends_on: Date.new(2030, 8, 31), status: :draft
    )
    Grade.find_or_create_by!(level: 2) { |record| record.name = "Second Secondary" }

    post "/api/academic_years/#{target.id}/copy_content", params: { source_year_id: source.id },
      headers: authorization_header(token), as: :json
    assert_response :success
    assert_equal source.branches.count, target.branches.count
    assert target.branches.first.draft?

    post "/api/academic_years/#{target.id}/rollover_students", params: { source_year_id: source.id },
      headers: authorization_header(token), as: :json
    assert_response :success
    assert_equal 1, response.parsed_body["moved_count"]
    assert target.reload.active?
    assert_equal 2, target.student_enrollments.first.grade.level
  end

  private

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
