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

  private

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
