require "test_helper"

class Api::DevicesControllerTest < ActionDispatch::IntegrationTest
  test "lists only the authenticated student's active devices" do
    student = create_student
    other_student = create_student
    current_device = register_device(student, "current-device")
    other_device = register_device(student, "other-device")
    register_device(other_student, "unrelated-device")
    token = Sessions::Start.call(user: student.user, device_registration: current_device).raw_token

    get "/api/devices", headers: authorization_header(token)

    assert_response :success
    assert_equal [ current_device.id, other_device.id ].sort, response.parsed_body["devices"].pluck("id").sort
    assert_equal current_device.id, response.parsed_body["devices"].find { |device| device["current"] }["id"]
    assert_equal 3, response.parsed_body["limit"]
  end

  test "removes another device and revokes its session" do
    student = create_student
    removable_device = register_device(student, "removable-device")
    removed_session = Sessions::Start.call(user: student.user, device_registration: removable_device).session
    current_device = register_device(student, "current-device")
    token = Sessions::Start.call(user: student.user, device_registration: current_device).raw_token

    delete "/api/devices/#{removable_device.id}", headers: authorization_header(token)

    assert_response :no_content
    assert removable_device.reload.removed?
    assert removed_session.reload.revoked?
  end

  test "creates one pending removal request during the self-removal cooldown" do
    student = create_student
    current_device = register_device(student, "current-device")
    requested_device = register_device(student, "requested-device")
    student.device_registrations.create!(
      device_fingerprint_digest: "f" * 64,
      status: :removed,
      last_seen_at: 1.day.ago,
      last_self_removed_at: 1.day.ago,
      removed_at: 1.day.ago
    )
    token = Sessions::Start.call(user: student.user, device_registration: current_device).raw_token

    2.times do
      post "/api/devices/#{requested_device.id}/removal_request", params: {
        removal_request: { reason: "The device was sold" }
      }, headers: authorization_header(token), as: :json
      assert_response :created
    end

    assert_equal 1, student.user.support_requests.device_removal.pending.count
  end

  test "rejects access from a parent" do
    parent = create_parent
    token = Sessions::Start.call(user: parent.user).raw_token

    get "/api/devices", headers: authorization_header(token)

    assert_response :forbidden
  end

  private

  def register_device(student, fingerprint)
    Devices::Register.call(
      student_profile: student,
      fingerprint:,
      attributes: { device_name: fingerprint, browser: "Test Browser", os: "Test OS" }
    )
  end

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
