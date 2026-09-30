require "test_helper"

class Api::LectureViewersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_user(role: :teacher)
    @teacher_token = Sessions::Start.call(user: @teacher).raw_token
    _year, _grade, _branch, _chapter, lesson = create_curriculum
    @lecture = lesson.lectures.create!(title: "Watched lecture", position: 1,
      status: :published, duration_seconds: 100)
  end

  test "teacher sees actual watched time, last position, and status" do
    student = create_student
    student.user.update!(name: "Viewer")
    student.lecture_watch_events.create!(lecture: @lecture, started_at: 10.minutes.ago,
      watched_seconds: 35, last_position_seconds: 80)
    student.lecture_watch_events.create!(lecture: @lecture, started_at: 5.minutes.ago,
      watched_seconds: 40, last_position_seconds: 25)

    get "/api/lectures/#{@lecture.id}/viewers", headers: authorization_header(@teacher_token)

    assert_response :success
    viewer = response.parsed_body.fetch("viewers").sole
    assert_equal student.user_id, viewer.fetch("student_id")
    assert_equal 75, viewer.fetch("progress_percent")
    assert_equal "watched", viewer.fetch("status")
    assert_equal 25, viewer.fetch("last_position_seconds")
  end

  test "students cannot see other students' viewing history" do
    student = create_student
    token = start_test_session(student.user).raw_token

    get "/api/lectures/#{@lecture.id}/viewers", headers: authorization_header(token)

    assert_response :forbidden
  end

  test "only assistants granted content permission can see viewers" do
    assistant = create_user(role: :assistant)
    profile = AssistantProfile.create!(user: assistant)
    token = Sessions::Start.call(user: assistant).raw_token

    get "/api/lectures/#{@lecture.id}/viewers", headers: authorization_header(token)
    assert_response :forbidden

    profile.assistant_permissions.create!(permission_key: "manage_content", enabled: true)
    get "/api/lectures/#{@lecture.id}/viewers", headers: authorization_header(token)
    assert_response :success
  end

  private

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
