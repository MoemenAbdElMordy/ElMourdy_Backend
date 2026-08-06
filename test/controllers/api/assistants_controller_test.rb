require "test_helper"

class Api::AssistantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    teacher = create_user(role: :teacher)
    @token = Sessions::Start.call(user: teacher).raw_token
  end

  test "teacher creates an assistant with selected permissions" do
    post "/api/assistants", params: {
      assistant: {
        name: "New Assistant",
        phone: "01212345678",
        email: "assistant@example.test",
        title: "Student Support",
        password: "ValidPassword123!",
        password_confirmation: "ValidPassword123!",
        permissions: %w[manage_students manage_devices]
      }
    }, headers: authorization_header(@token), as: :json

    assert_response :created
    assert_equal %w[manage_students manage_devices].sort,
      response.parsed_body.dig("assistant", "permissions").sort
  end

  test "teacher archives an assistant" do
    assistant = create_user(role: :assistant)
    AssistantProfile.create!(user: assistant)

    delete "/api/assistants/#{assistant.id}", headers: authorization_header(@token)

    assert_response :no_content
    assert assistant.reload.archived?
  end

  private

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
