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
    assert_equal false, lectures.first.fetch("has_thumbnail")
    assert_equal 1, lectures.first.dig("grade", "level")
  end

  test "guest sees a free lecture using a video uploaded for another lecture but not a scheduled one" do
    _year, _grade, _branch, _chapter, lesson = create_curriculum
    paid = lesson.lectures.create!(title: "Original Upload", position: 1, status: :published)
    asset = paid.video_assets.create!(
      processing_status: :ready,
      original_file_key: "videos/shared/original/source.mp4",
      duration_seconds: 600,
      available_qualities: [ "480p" ]
    )
    asset.video_variants.create!(
      quality: "480p", status: :ready,
      file_key: "videos/shared/hls/480p/index.m3u8", size_bytes: 1024
    )
    visible = lesson.lectures.create!(
      title: "Reused Free Video", position: 2, status: :published,
      is_free: true, selected_video_asset: asset, duration_seconds: 1200
    )
    lesson.lectures.create!(
      title: "Scheduled Free Video", position: 3, status: :published,
      is_free: true, selected_video_asset: asset, publish_at: 2.days.from_now
    )

    get "/api/free_lectures"

    assert_response :success
    assert_equal [ visible.id ], response.parsed_body.fetch("lectures").pluck("id")
    assert_equal [ "480p" ], response.parsed_body.fetch("lectures").first.fetch("available_qualities")
    assert_equal 600, response.parsed_body.fetch("lectures").first.fetch("duration_seconds")
  end

  test "guest sees published free YouTube lectures without uploaded variants" do
    _year, _grade, _branch, _chapter, lesson = create_curriculum
    lesson.update!(is_free: true)
    youtube = lesson.lectures.create!(
      title: "Free YouTube Lecture", position: 1, status: :published,
      video_source_type: :youtube, youtube_video_id: "DkJYaDCf48s",
      duration_seconds: 420
    )
    lesson.lectures.create!(
      title: "Scheduled YouTube Lecture", position: 2, status: :published,
      video_source_type: :youtube, youtube_video_id: "sBr7SWFXW7o",
      publish_at: 2.days.from_now
    )
    lesson.lectures.create!(
      title: "Draft YouTube Lecture", position: 3, status: :draft,
      video_source_type: :youtube, youtube_video_id: "kd79Fa-JicY"
    )

    get "/api/free_lectures"

    assert_response :success
    lectures = response.parsed_body.fetch("lectures")
    assert_equal [youtube.id], lectures.pluck("id")
    assert_equal 420, lectures.first.fetch("duration_seconds")
    assert_equal [], lectures.first.fetch("available_qualities")
  end

  test "guest can load a thumbnail only for a playable free lecture" do
    _year, _grade, _branch, _chapter, lesson = create_curriculum
    lesson.update!(is_free: true)
    lecture = lesson.lectures.create!(
      title: "Free Lecture With Thumbnail",
      position: 1,
      status: :published,
      thumbnail_key: "thumbnails/lectures/free-cover.webp"
    )
    asset = lecture.video_assets.create!(
      processing_status: :ready,
      original_file_key: "videos/free/original/source.mp4",
      available_qualities: [ "480p" ]
    )
    asset.video_variants.create!(
      quality: "480p",
      status: :ready,
      file_key: "videos/free/hls/480p/index.m3u8",
      size_bytes: 1024
    )

    storage = Videos::Storage.build
    storage.put(lecture.thumbnail_key, StringIO.new("thumbnail-data"))
    get "/api/free_lectures/#{lecture.id}/thumbnail"

    assert_response :success
    assert_equal "thumbnail-data", response.body
    assert_match "public", response.headers.fetch("Cache-Control")
  ensure
    storage&.delete(lecture&.thumbnail_key)
  end
end
