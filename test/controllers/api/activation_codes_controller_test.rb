require "test_helper"

class Api::ActivationCodesControllerTest < ActionDispatch::IntegrationTest
  test "teacher generates lists and exports an encrypted code batch" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    year, grade, _branch, _chapter, lesson = create_curriculum

    post "/api/activation_code_batches", params: {
      activation_code_batch: {
        lesson_id: lesson.id, academic_year_id: year.id, grade_id: grade.id,
        name: "September Codes", quantity: 3, expires_on: Date.current + 30.days
      }
    }, headers: authorization_header(token), as: :json

    assert_response :created
    assert_equal 3, response.parsed_body.fetch("generated_codes").length
    batch_id = response.parsed_body.dig("batch", "id")
    assert ActivationCode.where(activation_code_batch_id: batch_id).all? { |code| code.code_ciphertext.exclude?("ELM-") }

    get "/api/activation_code_batches", headers: authorization_header(token)
    assert_response :success
    assert_equal "September Codes", response.parsed_body.dig("batches", 0, "name")

    get "/api/activation_code_batches/#{batch_id}/export", headers: authorization_header(token)
    assert_response :success
    assert_includes response.body, "code,status,lesson"
    assert_includes response.body, "ELM-"
  end

  test "student redeems a matching code and cannot reuse it" do
    teacher = create_user(role: :teacher)
    student = create_student
    year, grade, _branch, _chapter, lesson = create_curriculum
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, status: :active, enrolled_at: Time.current)
    raw_code = generated_code(teacher:, year:, grade:, lesson:)
    token = student_token(student)

    post "/api/activation_codes/redeem", params: { code: raw_code }, headers: authorization_header(token), as: :json
    assert_response :created
    assert_equal lesson.id, response.parsed_body.dig("access_grant", "lesson_id")

    post "/api/activation_codes/redeem", params: { code: raw_code }, headers: authorization_header(token), as: :json
    assert_response :unprocessable_entity
  end

  test "student cannot redeem a code for another grade" do
    teacher = create_user(role: :teacher)
    student = create_student
    year, grade, _branch, _chapter, lesson = create_curriculum
    other_grade = Grade.create!(name: "Other Grade", level: available_level)
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade: other_grade, status: :active, enrolled_at: Time.current)
    raw_code = generated_code(teacher:, year:, grade:, lesson:)

    post "/api/activation_codes/redeem", params: { code: raw_code }, headers: authorization_header(student_token(student)), as: :json

    assert_response :unprocessable_entity
    assert_not ActivationCode.find_by!(code_digest: Security::DigestValue.call(raw_code)).redeemed?
  end

  test "teacher disables and deletes only unused codes" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    year, grade, _branch, _chapter, lesson = create_curriculum
    raw_code = generated_code(teacher:, year:, grade:, lesson:)
    code = ActivationCode.find_by!(code_digest: Security::DigestValue.call(raw_code))

    patch "/api/activation_codes/#{code.id}", headers: authorization_header(token)
    assert_response :success
    assert code.reload.disabled?

    delete "/api/activation_codes/#{code.id}", headers: authorization_header(token)
    assert_response :unprocessable_entity
  end

  test "teacher grants and revokes manual lesson access" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    student = create_student
    year, grade, _branch, _chapter, lesson = create_curriculum
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, status: :active, enrolled_at: Time.current)

    post "/api/lesson_access_grants", params: {
      lesson_access_grant: { student_user_id: student.user_id, lesson_id: lesson.id, academic_year_id: year.id, expires_on: year.ends_on }
    }, headers: authorization_header(token), as: :json
    assert_response :created
    grant_id = response.parsed_body.dig("access_grant", "id")
    assert_equal "manual", response.parsed_body.dig("access_grant", "source")

    patch "/api/lesson_access_grants/#{grant_id}", params: { lesson_access_grant: { status: "revoked" } }, headers: authorization_header(token), as: :json
    assert_response :success
    assert_equal "revoked", response.parsed_body.dig("access_grant", "status")
  end

  private

  def generated_code(teacher:, year:, grade:, lesson:)
    ActivationCodes::GenerateBatch.call(
      attributes: { lesson_id: lesson.id, academic_year_id: year.id, grade_id: grade.id, name: "Test", quantity: 1, expires_on: Date.current + 30.days },
      created_by_user: teacher
    ).raw_codes.first
  end

  def student_token(student)
    device = student.device_registrations.create!(device_fingerprint_digest: Security::DigestValue.call(SecureRandom.hex(12)), status: :active)
    Sessions::Start.call(user: student.user, device_registration: device).raw_token
  end

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def available_level
    (1..3).detect { |level| !Grade.exists?(level:) }
  end
end
