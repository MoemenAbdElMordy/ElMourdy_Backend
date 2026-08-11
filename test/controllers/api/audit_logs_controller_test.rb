require "test_helper"

class Api::AuditLogsControllerTest < ActionDispatch::IntegrationTest
  test "teacher sees only assistant activity with user friendly descriptions" do
    teacher = create_user(role: :teacher)
    teacher_token = Sessions::Start.call(user: teacher).raw_token
    assistant = create_user(role: :assistant)
    profile = AssistantProfile.create!(user: assistant)
    profile.assistant_permissions.create!(permission_key: "manage_academic_years", enabled: true)
    assistant_token = Sessions::Start.call(user: assistant).raw_token
    year, = create_academic_setup

    patch "/api/academic_years/#{year.id}", params: { academic_year: { name: "Updated year" } },
      headers: auth(assistant_token), as: :json
    assert_response :success

    patch "/api/academic_years/#{year.id}", params: { academic_year: { name: "Teacher update" } },
      headers: auth(teacher_token), as: :json
    assert_response :success

    get "/api/audit_logs", headers: auth(teacher_token)
    assert_response :success
    logs = response.parsed_body.fetch("audit_logs")
    assert_equal [ assistant.id ], logs.map { |log| log.dig("assistant", "id") }.uniq
    assert_equal "academic_year_updated", logs.first["description_key"]
    assert_equal "academic_years", logs.first["section_key"]
    assert_not logs.first.key?("target")
    assert_not logs.first.key?("ip_address")
  end

  private

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
