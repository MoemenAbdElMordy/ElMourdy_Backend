require "test_helper"

class Api::LectureThumbnailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_user(role: :teacher)
    @token = Sessions::Start.call(user: @teacher).raw_token
    _year, _grade, _branch, _chapter, lesson = create_curriculum
    @lecture = lesson.lectures.create!(title: "Thumbnail Lecture", position: 1, status: :published)
  end

  test "teacher uploads reads and removes a lecture thumbnail" do
    put "/api/lectures/#{@lecture.id}/thumbnail",
      params: "test-image-content",
      headers: authorization_header.merge("Content-Type" => "image/png")

    assert_response :success
    assert @lecture.reload.thumbnail_key.present?

    get "/api/lectures/#{@lecture.id}/thumbnail", headers: authorization_header
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "test-image-content", response.body

    delete "/api/lectures/#{@lecture.id}/thumbnail", headers: authorization_header
    assert_response :no_content
    assert_nil @lecture.reload.thumbnail_key
  end

  test "thumbnail upload rejects unsupported file types" do
    put "/api/lectures/#{@lecture.id}/thumbnail",
      params: "unsupported",
      headers: authorization_header.merge("Content-Type" => "image/svg+xml")

    assert_response :unprocessable_entity
    assert_nil @lecture.reload.thumbnail_key
  end

  private

  def authorization_header
    { "Authorization" => "Bearer #{@token}" }
  end
end
