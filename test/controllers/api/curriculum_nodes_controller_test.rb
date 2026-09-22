require "test_helper"

class Api::CurriculumNodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_user(role: :teacher)
    @token = Sessions::Start.call(user: @teacher).raw_token
    _year, _grade, @branch, _chapter, @lesson = create_curriculum
  end

  test "opening and cancelling requires no request and creates nothing" do
    assert_no_difference ["CurriculumNode.count", "Chapter.count", "Lesson.count", "Lecture.count"] do
      get "/api/curriculum", params: {
        academic_year_id: @branch.academic_year_id, grade_id: @branch.grade_id
      }, headers: authorization_header(@token)
      assert_response :success
    end
  end

  test "teacher creates exactly one idempotent folder" do
    headers = authorization_header(@token).merge("Idempotency-Key" => "folder-request-1")
    assert_difference "CurriculumNode.count", 1 do
      2.times do
        post "/api/curriculum_nodes", params: {
          branch_id: @branch.id, node: { title: "One folder" }
        }, headers:, as: :json
        assert_response :created
      end
    end
    assert_equal "One folder", response.parsed_body.dig("node", "title")
  end

  test "assistant without content permission and student cannot mutate folders" do
    assistant = create_user(role: :assistant)
    AssistantProfile.create!(user: assistant)
    assistant_token = Sessions::Start.call(user: assistant).raw_token
    student = create_student
    student_token = start_test_session(student.user).raw_token

    [assistant_token, student_token].each do |token|
      assert_no_difference "CurriculumNode.count" do
        post "/api/curriculum_nodes", params: {
          branch_id: @branch.id, node: { title: "Forbidden", request_key: SecureRandom.uuid }
        }, headers: authorization_header(token), as: :json
        assert_response :forbidden
      end
    end
  end

  test "move and reorder are atomic and invalid cycles leave tree unchanged" do
    first = create_folder("First", "first")
    second = create_folder("Second", "second", first.fetch("id"))

    patch "/api/curriculum_nodes/#{first.fetch('id')}/move", params: {
      branch_id: @branch.id, node: { parent_id: second.fetch("id") }
    }, headers: authorization_header(@token), as: :json
    assert_response :unprocessable_entity
    assert_nil CurriculumNode.find(first.fetch("id")).parent_id

    patch "/api/curriculum_nodes/#{second.fetch('id')}/move", params: {
      branch_id: @branch.id, node: { parent_id: nil }
    }, headers: authorization_header(@token), as: :json
    assert_response :success

    patch "/api/curriculum_nodes/reorder", params: {
      branch_id: @branch.id, node: { parent_id: nil }, ordered_ids: [second.fetch("id"), first.fetch("id")]
    }, headers: authorization_header(@token), as: :json
    assert_response :no_content
    assert_equal [second.fetch("id"), first.fetch("id")], CurriculumNode.where(branch: @branch, parent_id: nil).ordered.pluck(:id)
  end

  test "backfill can be repeated and curriculum returns the node tree" do
    lecture = @lesson.lectures.create!(title: "Saved lecture", position: 1, status: :published)
    2.times do
      post "/api/curriculum_nodes/backfill", params: { branch_id: @branch.id }, headers: authorization_header(@token), as: :json
      assert_response :success
    end
    assert_equal 3, CurriculumNode.count

    get "/api/curriculum", params: {
      academic_year_id: @branch.academic_year_id, grade_id: @branch.grade_id
    }, headers: authorization_header(@token)
    assert_response :success
    node_lecture = response.parsed_body.dig("curriculum", "branches", 0, "nodes", 0, "children", 0, "children", 0)
    assert_equal lecture.id, node_lecture.fetch("lecture_id")
  end

  test "student receives the published presentation tree with access state" do
    lecture = @lesson.lectures.create!(title: "Student lecture", position: 1, status: :published)
    Curriculum::BackfillFolderTree.call(branch: @branch)
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: @branch.academic_year,
      grade: @branch.grade, status: :active, enrolled_at: Time.current)
    device = student.device_registrations.create!(
      device_fingerprint_digest: Security::DigestValue.call(SecureRandom.hex(12)), status: :active)
    token = Sessions::Start.call(user: student.user, device_registration: device).raw_token

    get "/api/curriculum", headers: authorization_header(token)

    assert_response :success
    node = response.parsed_body.dig("curriculum", "branches", 0, "nodes", 0, "children", 0, "children", 0)
    assert_equal lecture.id, node.fetch("lecture_id")
    assert_equal false, node.dig("lecture", "has_access")
  end

  test "first lecture in an empty subject creates one hidden legacy anchor and one presentation node" do
    year, grade = create_academic_setup
    branch = Branch.create!(academic_year: year, grade:, title: "Empty subject", position: 1, status: :published)

    assert_difference ["Chapter.count", "Lesson.count", "Lecture.count", "CurriculumNode.count"], 1 do
      post "/api/lectures", params: {
        lecture: { branch_id: branch.id, parent_node_id: nil, title: "First lecture", status: "published" }
      }, headers: authorization_header(@token).merge("Idempotency-Key" => "first-empty-lecture"), as: :json
      assert_response :created
    end

    assert_equal "lecture", branch.curriculum_nodes.first.kind
    assert_equal 1, branch.chapters.count
    assert_equal 1, branch.chapters.first.lessons.count
  end

  test "a new folder lecture never inherits a free legacy lesson" do
    @lesson.update!(is_free: true)
    post "/api/lectures", params: {
      lecture: { branch_id: @branch.id, title: "Paid lecture", status: "published", is_free: false }
    }, headers: authorization_header(@token), as: :json

    assert_response :created
    lecture = Lecture.find(response.parsed_body.dig("lecture", "id"))
    assert_not_equal @lesson.id, lecture.lesson_id
    assert_equal false, lecture.lesson.is_free
    assert_equal "Internal content storage", lecture.lesson.chapter.title
  end

  test "internal entitlement containers are absent from student and teacher curriculum" do
    Curriculum::LegacyAnchor.ensure_for!(@branch)
    get "/api/curriculum", params: {
      academic_year_id: @branch.academic_year_id, grade_id: @branch.grade_id
    }, headers: authorization_header(@token)

    assert_response :success
    titles = response.parsed_body.dig("curriculum", "branches", 0, "chapters").map { |item| item.fetch("title") }
    assert_not_includes titles, "Internal content storage"
  end

  private

  def create_folder(title, key, parent_id = nil)
    post "/api/curriculum_nodes", params: {
      branch_id: @branch.id, node: { title:, parent_id: }
    }, headers: authorization_header(@token).merge("Idempotency-Key" => key), as: :json
    assert_response :created
    response.parsed_body.fetch("node")
  end

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
