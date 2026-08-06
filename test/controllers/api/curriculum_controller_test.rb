require "test_helper"

class Api::CurriculumControllerTest < ActionDispatch::IntegrationTest
  test "teacher manages and reorders the complete curriculum hierarchy" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    year, grade = create_academic_setup

    branch_one = create_resource("branches", { academic_year_id: year.id, grade_id: grade.id, title: "Grammar", status: "draft" }, token)
    branch_two = create_resource("branches", { academic_year_id: year.id, grade_id: grade.id, title: "Literature", status: "published" }, token)
    chapter = create_resource("chapters", { branch_id: branch_one.fetch("id"), title: "Foundations", status: "published" }, token)
    lesson = create_resource("lessons", { chapter_id: chapter.fetch("id"), title: "Introduction", status: "published", is_free: true }, token)
    lecture = create_resource("lectures", { lesson_id: lesson.fetch("id"), title: "First Lecture", status: "published", duration_seconds: 600 }, token)

    patch "/api/branches/reorder", params: {
      academic_year_id: year.id, grade_id: grade.id, ordered_ids: [ branch_two.fetch("id"), branch_one.fetch("id") ]
    }, headers: authorization_header(token), as: :json

    assert_response :no_content
    assert_equal [ branch_two.fetch("id"), branch_one.fetch("id") ], Branch.where(academic_year: year, grade: grade).ordered.pluck(:id)

    patch "/api/lectures/#{lecture.fetch('id')}", params: { lecture: { title: "Updated Lecture", status: "hidden" } }, headers: authorization_header(token), as: :json
    assert_response :success
    assert_equal "hidden", response.parsed_body.dig("lecture", "status")

    get "/api/curriculum", params: { academic_year_id: year.id, grade_id: grade.id }, headers: authorization_header(token)
    assert_response :success
    assert_equal 2, response.parsed_body.dig("curriculum", "branches").size
    assert_equal "Foundations", response.parsed_body.dig("curriculum", "branches", 1, "chapters", 0, "title")
  end

  test "student sees only currently published curriculum for the active enrollment" do
    year, grade, branch, chapter, lesson = create_curriculum
    lecture = lesson.lectures.create!(title: "Published Lecture", position: 1, status: :published)
    lesson.lectures.create!(title: "Hidden Lecture", position: 2, status: :hidden)
    branch.chapters.create!(title: "Draft Chapter", position: 2, status: :draft)
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade: grade, status: :active, enrolled_at: Time.current)
    device = student.device_registrations.create!(device_fingerprint_digest: Security::DigestValue.call(SecureRandom.hex(12)), status: :active)
    token = Sessions::Start.call(user: student.user, device_registration: device).raw_token

    get "/api/curriculum", headers: authorization_header(token)

    assert_response :success
    assert_equal grade.id, response.parsed_body.dig("curriculum", "grade", "id")
    assert_equal [ chapter.id ], response.parsed_body.dig("curriculum", "branches", 0, "chapters").pluck("id")
    assert_equal [ lecture.id ], response.parsed_body.dig("curriculum", "branches", 0, "chapters", 0, "lessons", 0, "lectures").pluck("id")
  end

  test "assistant requires content permission" do
    assistant = create_user(role: :assistant)
    AssistantProfile.create!(user: assistant)
    token = Sessions::Start.call(user: assistant).raw_token

    get "/api/curriculum", headers: authorization_header(token)

    assert_response :forbidden
  end

  test "deletion returns a conflict while dependent content exists" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    _year, _grade, branch, = create_curriculum

    delete "/api/branches/#{branch.id}", headers: authorization_header(token)

    assert_response :conflict
    assert_equal "dependency_conflict", response.parsed_body.dig("error", "code")
    assert Branch.exists?(branch.id)
  end

  test "teacher can delete empty content from the bottom up" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    year, grade = create_academic_setup
    branch = Branch.create!(academic_year: year, grade: grade, title: "Empty", position: 1)

    delete "/api/branches/#{branch.id}", headers: authorization_header(token)

    assert_response :no_content
    assert_not Branch.exists?(branch.id)
  end

  private

  def create_resource(resource, attributes, token)
    singular = resource.singularize
    post "/api/#{resource}", params: { singular => attributes }, headers: authorization_header(token), as: :json
    assert_response :created
    response.parsed_body.fetch(singular)
  end

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
