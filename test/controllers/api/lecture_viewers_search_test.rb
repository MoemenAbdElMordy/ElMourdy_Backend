require "test_helper"

class Api::LectureViewersSearchTest < ActionDispatch::IntegrationTest
  test "teacher searches lecture viewers by center and phone" do
    year, grade, _branch, _chapter, lesson = create_curriculum
    lecture = lesson.lectures.create!(title: "Video", position: 1, status: :published,
      video_source_type: :youtube, youtube_video_id: "abcdefghijk", duration_seconds: 100)
    matching = create_student
    matching.update!(center_name: "Bright Center")
    other = create_student
    not_started = create_student
    not_started.user.update!(name: "Student Without Views")
    StudentEnrollment.create!(student_profile: not_started, academic_year: year, grade: grade,
      status: :active, enrolled_at: Time.current)
    [matching, other].each do |profile|
      profile.lecture_watch_events.create!(lecture:, started_at: Time.current,
        watched_seconds: profile == other ? 80 : 30, last_position_seconds: profile == other ? 80 : 30)
    end
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    headers = { "Authorization" => "Bearer #{token}" }

    get "/api/lectures/#{lecture.id}/viewers", params: { query: "Bright" }, headers: headers
    assert_response :success
    assert_equal [matching.user_id], response.parsed_body.fetch("viewers").pluck("student_id")
    assert_equal "Bright Center", response.parsed_body.dig("viewers", 0, "center_name")

    get "/api/lectures/#{lecture.id}/viewers", params: { query: matching.user.phone_e164 }, headers: headers
    assert_response :success
    assert_equal [matching.user_id], response.parsed_body.fetch("viewers").pluck("student_id")

    get "/api/lectures/#{lecture.id}/viewers", params: { query: "Without Views" }, headers: headers
    assert_response :success
    assert_equal [not_started.user_id], response.parsed_body.fetch("viewers").pluck("student_id")
    assert_equal "not_watched", response.parsed_body.dig("viewers", 0, "status")

    get "/api/lectures/#{lecture.id}/viewers", params: { watch_status: "not_watched" }, headers: headers
    assert_response :success
    assert_equal [not_started.user_id], response.parsed_body.fetch("viewers").pluck("student_id")

    get "/api/lectures/#{lecture.id}/viewers", params: { watch_status: "watched" }, headers: headers
    assert_response :success
    assert_equal [other.user_id], response.parsed_body.fetch("viewers").pluck("student_id")

    get "/api/lectures/#{lecture.id}/viewers", params: { watch_status: "partial", query: "Bright" }, headers: headers
    assert_response :success
    assert_equal [matching.user_id], response.parsed_body.fetch("viewers").pluck("student_id")
  end
end
