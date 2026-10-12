require "test_helper"

class Api::ActivationCodesControllerTest < ActionDispatch::IntegrationTest
  test "teacher generates lists and exports an encrypted code batch" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    year, grade, _branch, _chapter, lesson = create_curriculum

    post "/api/activation_code_batches", params: {
      activation_code_batch: {
        name: "September Codes", quantity: 3, expires_on: Date.current + 30.days
      }
    }, headers: authorization_header(token), as: :json

    assert_response :created
    assert_equal 3, response.parsed_body.fetch("generated_codes").length
    assert response.parsed_body.dig("batch", "generic")
    batch_id = response.parsed_body.dig("batch", "id")
    assert ActivationCode.where(activation_code_batch_id: batch_id).all? { |code| code.code_ciphertext.exclude?("ELM-") }

    get "/api/activation_code_batches", headers: authorization_header(token)
    assert_response :success
    assert_equal "September Codes", response.parsed_body.dig("batches", 0, "name")

    get "/api/activation_code_batches/#{batch_id}/export", headers: authorization_header(token)
    assert_response :success
    assert_includes response.body, "code,status,target"
    assert_includes response.body, "ELM-"

    get "/api/activation_code_batches/#{batch_id}/export.docx", headers: authorization_header(token)
    assert_response :success
    assert_equal Documents::DocxBuilder::CONTENT_TYPE, response.media_type
    Zip::File.open_buffer(response.body) do |archive|
      assert_includes archive.find_entry("word/document.xml").get_input_stream.read, "Activation Code Batch"
    end
  end

  test "student uses a generic code once to unlock the selected paid lecture" do
    teacher = create_user(role: :teacher)
    student = create_student
    year, grade, _branch, _chapter, lesson = create_curriculum
    lecture = Lecture.create!(lesson:, title: "Paid Lecture", position: 1, status: :published,
      video_source_type: :youtube, youtube_video_id: "AbCdEf12345")
    another_lecture = Lecture.create!(lesson:, title: "Another Lecture", position: 2, status: :published)
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, status: :active, enrolled_at: Time.current)
    post "/api/activation_code_batches", params: {
      activation_code_batch: { name: "Generic Codes", quantity: 1, expires_on: Date.current + 30.days }
    }, headers: authorization_header(Sessions::Start.call(user: teacher).raw_token), as: :json
    assert_response :created
    raw_code = response.parsed_body.fetch("generated_codes").first
    token = student_token(student)

    get "/api/lectures/#{lecture.id}/video_playback", headers: authorization_header(token)
    assert_response :forbidden

    post "/api/activation_codes/redeem", params: {
      code: raw_code, lecture_id: lecture.id
    }, headers: authorization_header(token), as: :json

    assert_response :created
    assert_equal "lecture", response.parsed_body.dig("access_grant", "access_type")
    assert_equal lecture.id, response.parsed_body.dig("access_grant", "lecture_id")
    assert Videos::Access.allowed?(user: student.user, lecture:)
    assert_not Videos::Access.allowed?(user: student.user, lecture: another_lecture)

    get "/api/lectures/#{lecture.id}/video_playback", headers: authorization_header(token)
    assert_response :success
    assert_equal "youtube", response.parsed_body.dig("playback", "source_type")
    assert_equal "AbCdEf12345", response.parsed_body.dig("playback", "youtube_video_id")

    get "/api/curriculum", headers: authorization_header(token)
    assert_response :success
    lectures = response.parsed_body.dig("curriculum", "branches", 0, "chapters", 0, "lessons", 0, "lectures")
    assert_equal true, lectures.find { |item| item.fetch("id") == lecture.id }.fetch("has_access")
    assert_equal false, lectures.find { |item| item.fetch("id") == another_lecture.id }.fetch("has_access")

    post "/api/activation_codes/redeem", params: {
      code: raw_code, lecture_id: another_lecture.id
    }, headers: authorization_header(token), as: :json

    assert_response :unprocessable_entity
    assert_not Videos::Access.allowed?(user: student.user, lecture: another_lecture)
  end

  test "does not consume a code for a hidden or scheduled lecture" do
    teacher = create_user(role: :teacher)
    student = create_student
    year, grade, _branch, _chapter, lesson = create_curriculum
    lecture = Lecture.create!(lesson:, title: "Unreleased Lecture", position: 1, status: :draft)
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, status: :active, enrolled_at: Time.current)
    raw_code = ActivationCodes::GenerateBatch.call(
      attributes: { name: "Future Codes", quantity: 1, expires_on: Date.current + 30.days },
      created_by_user: teacher
    ).raw_codes.first
    token = student_token(student)

    post "/api/activation_codes/redeem", params: { code: raw_code, lecture_id: lecture.id },
      headers: authorization_header(token), as: :json
    assert_response :unprocessable_entity
    assert ActivationCode.find_by!(code_digest: Security::DigestValue.call(raw_code)).unused?

    lecture.update!(status: :published, publish_at: 1.day.from_now)
    post "/api/activation_codes/redeem", params: { code: raw_code, lecture_id: lecture.id },
      headers: authorization_header(token), as: :json
    assert_response :unprocessable_entity
    assert ActivationCode.find_by!(code_digest: Security::DigestValue.call(raw_code)).unused?
  end

  test "assistant can generate and export codes only with manage codes permission" do
    assistant = create_user(role: :assistant)
    profile = AssistantProfile.create!(user: assistant)
    token = Sessions::Start.call(user: assistant).raw_token
    params = { activation_code_batch: { name: "Assistant Codes", quantity: 2, expires_on: Date.current + 30.days } }

    post "/api/activation_code_batches", params:, headers: authorization_header(token), as: :json
    assert_response :forbidden
    assert_not ActivationCodeBatch.exists?(name: "Assistant Codes")

    profile.assistant_permissions.create!(permission_key: "manage_codes", enabled: true)
    post "/api/activation_code_batches", params:, headers: authorization_header(token), as: :json
    assert_response :created
    assert_equal 2, response.parsed_body.fetch("generated_codes").size
    batch_id = response.parsed_body.dig("batch", "id")

    get "/api/activation_code_batches/#{batch_id}/export", headers: authorization_header(token)
    assert_response :success
    assert_includes response.body, "ELM-"
  end

  test "rejects a new batch whose codes would already be expired" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    post "/api/activation_code_batches", params: {
      activation_code_batch: { name: "Expired Codes", quantity: 1, expires_on: Date.yesterday }
    }, headers: authorization_header(token), as: :json

    assert_response :unprocessable_entity
    assert_not ActivationCodeBatch.exists?(name: "Expired Codes")
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
