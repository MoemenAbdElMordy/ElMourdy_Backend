require "test_helper"

class Api::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "registers and verifies a student" do
    year, grade = create_academic_setup
    post "/api/registrations/student", params: {
      registration: {
        name: "New Student",
        phone: "01012345678",
        parent_phone: "01112345678",
        birth_date: "2008-04-16",
        governorate: "Cairo",
        school: "Test School",
        email: "new.student@example.test",
        grade_level: grade.level,
        password: "ValidPassword123!",
        password_confirmation: "ValidPassword123!"
      }
    }, as: :json

    assert_response :created
    registration = response.parsed_body
    assert_equal "email", registration["verification_method"]
    assert_equal "n***@example.test", registration["email_hint"]
    assert registration["client_token"].present?

    post "/api/registrations/#{registration["registration_id"]}/status", params: {
      registration: {
        verification_id: registration["verification_id"],
        client_token: registration["client_token"]
      }
    }, as: :json
    assert_response :success
    assert_equal "pending", response.parsed_body["status"]

    post "/api/registrations/#{registration["registration_id"]}/verify", params: {
      registration: {
        verification_id: registration["verification_id"],
        code: delivered_code,
        device_fingerprint: "student-device"
      }
    }, as: :json

    assert_response :success
    assert response.parsed_body["token"].present?
    assert_equal "student", response.parsed_body.dig("user", "role")
    user = User.find(registration["registration_id"])
    assert user.phone_verified_at.present?
    assert_equal year, user.student_profile.student_enrollments.active.first.academic_year
    assert_equal grade, user.student_profile.student_enrollments.active.first.grade
    assert_equal "Test School", user.student_profile.school
    assert_equal "new.student@example.test", user.email
  end

  test "registers a parent only for a matching student and links the account" do
    create_student(parent_phone: "+201112345678")

    post "/api/registrations/parent", params: {
      registration: {
        name: "New Parent",
        phone: "01112345678",
        email: "new.parent@example.test",
        password: "ValidPassword123!",
        password_confirmation: "ValidPassword123!"
      }
    }, as: :json

    assert_response :created
    registration = response.parsed_body
    post "/api/registrations/#{registration["registration_id"]}/verify", params: {
      registration: {
        verification_id: registration["verification_id"],
        code: delivered_code
      }
    }, as: :json

    assert_response :success
    parent = User.find(registration["registration_id"]).parent_profile
    assert_equal 1, parent.student_parent_links.active.count
  end

  test "rejects matching student and parent phone numbers" do
    _year, grade = create_academic_setup
    post "/api/registrations/student", params: {
      registration: {
        name: "New Student",
        phone: "01012345678",
        parent_phone: "+201012345678",
        birth_date: "2008-04-16",
        governorate: "Cairo",
        grade_level: grade.level,
        email: "same.phone@example.test",
        password: "ValidPassword123!",
        password_confirmation: "ValidPassword123!"
      }
    }, as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body.dig("error", "details"),
      "Student and parent phone numbers must be different"
    assert_not User.exists?(phone_e164: "+201012345678")
  end

  test "rejects a parent phone that no student has registered" do
    post "/api/registrations/parent", params: {
      registration: {
        name: "Unknown Parent",
        phone: "01112345678",
        email: "unknown.parent@example.test",
        password: "ValidPassword123!",
        password_confirmation: "ValidPassword123!"
      }
    }, as: :json

    assert_response :unprocessable_entity
    assert_not User.exists?(phone_e164: "+201112345678")
  end

  private

  def delivered_code
    ActionMailer::Base.deliveries.last.body.encoded.match(/\b\d{6}\b/).to_s
  end
end
