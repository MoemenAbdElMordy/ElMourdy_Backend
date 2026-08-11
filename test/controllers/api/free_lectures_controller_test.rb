require "test_helper"

class Api::FreeLecturesControllerTest < ActionDispatch::IntegrationTest
  test "guest sees only published free lectures with playable video variants" do
    _year, _grade, _branch, _chapter, lesson = create_curriculum
    lesson.update!(is_free: true)
    playable = lesson.lectures.create!(
      title: "Free Lecture",
      position: 1,
      status: :published,
      duration_seconds: 600
    )
    asset = playable.video_assets.create!(
      processing_status: :ready,
      original_file_key: "videos/free/original/source.mp4",
      duration_seconds: 600,
      available_qualities: [ "480p" ]
    )
    asset.video_variants.create!(
      quality: "480p",
      status: :ready,
      file_key: "videos/free/hls/480p/index.m3u8",
      size_bytes: 1024
    )
    lesson.lectures.create!(title: "Free Without Video", position: 2, status: :published)
    paid_lesson = lesson.chapter.lessons.create!(title: "Paid Lesson", position: 2, status: :published)
    paid_lesson.lectures.create!(title: "Paid Lecture", position: 1, status: :published)

    get "/api/free_lectures"

    assert_response :success
    lectures = response.parsed_body.fetch("lectures")
    assert_equal [ playable.id ], lectures.pluck("id")
    assert_equal "Free Lecture", lectures.first.fetch("title")
    assert_equal [ "480p" ], lectures.first.fetch("available_qualities")
  end
end
