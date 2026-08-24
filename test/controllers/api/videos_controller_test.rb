require "test_helper"

class Api::VideosControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @year, @grade, _branch, _chapter, @lesson = create_curriculum
    @lecture = Lecture.create!(lesson: @lesson, title: "Recorded Lecture", position: 1, status: :published, duration_seconds: 100)
    @teacher = create_user(role: :teacher)
    @teacher_token = Sessions::Start.call(user: @teacher).raw_token
    @prefixes = []
  end

  teardown do
    @prefixes.each do |prefix|
      Videos::Storage.build.delete_prefix(prefix)
      Videos::Storage.staging.delete_prefix(prefix)
    end
  end

  test "teacher creates and completes a local direct upload" do
    post api_lecture_video_upload_url(@lecture), params: {
      filename: "lecture.mp4", content_type: "video/mp4", size_bytes: 12
    }, headers: authorization(@teacher_token), as: :json

    assert_response :created
    body = response.parsed_body
    asset = VideoAsset.find(body.dig("video_asset", "id"))
    @prefixes << File.dirname(File.dirname(asset.original_file_key))
    assert body.dig("upload", "requires_authentication")

    put URI(body.dig("upload", "url")).request_uri,
      params: "fake-video-data",
      headers: authorization(@teacher_token).merge("Content-Type" => "video/mp4")
    assert_response :no_content

    assert_enqueued_with(job: VideoProcessingJob, args: [ asset.id ]) do
      post complete_api_lecture_video_upload_url(@lecture),
        params: { video_asset_id: asset.id }, headers: authorization(@teacher_token), as: :json
    end
    assert_response :accepted
  end

  test "unsupported upload type is rejected" do
    post api_lecture_video_upload_url(@lecture), params: {
      filename: "lecture.exe", content_type: "application/octet-stream", size_bytes: 12
    }, headers: authorization(@teacher_token), as: :json

    assert_response :unprocessable_entity
    assert_equal "business_rule_violation", response.parsed_body.dig("error", "code")
  end

  test "teacher retries a failed video when the original file still exists" do
    prefix = "videos/#{SecureRandom.uuid}"
    @prefixes << prefix
    asset = VideoAsset.create!(
      lecture: @lecture,
      original_file_key: "#{prefix}/original/source.mp4",
      processing_status: :failed,
      created_by_user: @teacher
    )
    Videos::Storage.staging.put(asset.original_file_key, StringIO.new("video-data"))

    assert_enqueued_with(job: VideoProcessingJob, args: [ asset.id ]) do
      post retry_processing_api_video_asset_url(asset), headers: authorization(@teacher_token), as: :json
    end

    assert_response :accepted
    assert asset.reload.uploaded?
  end

  test "retry explains when the original video must be uploaded again" do
    asset = VideoAsset.create!(
      lecture: @lecture,
      original_file_key: "videos/missing/original/source.mp4",
      processing_status: :failed,
      created_by_user: @teacher
    )

    post retry_processing_api_video_asset_url(asset), headers: authorization(@teacher_token), as: :json

    assert_response :unprocessable_entity
    assert_equal "The original video is no longer available; upload it again", response.parsed_body.dig("error", "message")
  end

  test "teacher permanently deletes an unshared video and all stored qualities" do
    asset = ready_asset
    prefix = File.dirname(File.dirname(asset.original_file_key))
    playlist_key = "#{prefix}/hls/720p/index.m3u8"
    @lecture.update!(video_source_type: :uploaded, selected_video_asset: asset)

    delete api_video_asset_url(asset), headers: authorization(@teacher_token)

    assert_response :no_content
    assert_not VideoAsset.exists?(asset.id)
    assert_not Videos::Storage.build.exist?(playlist_key)
    assert_nil @lecture.reload.selected_video_asset_id
  end

  test "teacher permanently deletes a shared video and detaches every lecture" do
    asset = ready_asset
    other_lecture = Lecture.create!(lesson: @lesson, title: "Shared Lecture", position: 2, status: :published)
    @lecture.update!(selected_video_asset: asset)
    other_lecture.update!(video_source_type: :uploaded, selected_video_asset: asset)

    delete api_video_asset_url(asset), headers: authorization(@teacher_token)

    assert_response :no_content
    assert_not VideoAsset.exists?(asset.id)
    assert_nil @lecture.reload.selected_video_asset_id
    assert_nil other_lecture.reload.selected_video_asset_id
  end

  test "teacher deletes a lecture with its watch history and unshared stored videos" do
    student = create_student
    asset = ready_asset
    prefix = File.dirname(File.dirname(asset.original_file_key))
    @lecture.update!(selected_video_asset: asset)
    LectureWatchEvent.create!(student_profile: student, lecture: @lecture, started_at: Time.current)

    delete api_lecture_url(@lecture), headers: authorization(@teacher_token)

    assert_response :no_content
    assert_not Lecture.exists?(@lecture.id)
    assert_not VideoAsset.exists?(asset.id)
    assert_not LectureWatchEvent.where(lecture_id: @lecture.id).exists?
    assert_not Videos::Storage.build.exist?("#{prefix}/hls/720p/index.m3u8")
  end

  test "deleting a lecture preserves a video reused by another lecture" do
    asset = ready_asset
    other_lecture = Lecture.create!(lesson: @lesson, title: "Shared Lecture", position: 2, status: :published)
    @lecture.update!(selected_video_asset: asset)
    other_lecture.update!(video_source_type: :uploaded, selected_video_asset: asset)

    delete api_lecture_url(@lecture), headers: authorization(@teacher_token)

    assert_response :no_content
    assert_not Lecture.exists?(@lecture.id)
    assert_equal other_lecture.id, asset.reload.lecture_id
    assert_equal asset.id, other_lecture.reload.selected_video_asset_id
  end

  test "video library reports storage usage and whether deletion is safe" do
    asset = ready_asset
    @lecture.update!(video_source_type: :uploaded, selected_video_asset: asset)

    get api_video_assets_url, headers: authorization(@teacher_token)

    assert_response :success
    item = response.parsed_body.fetch("video_assets").find { |candidate| candidate.fetch("id") == asset.id }
    assert_equal 100, item.fetch("storage_size_bytes")
    assert_equal 1, item.fetch("used_by_lectures_count")
    assert item.fetch("can_delete")
  end

  test "authorized student progress requires verified watch time and ignores seeking" do
    student, token = enrolled_student_with_access
    asset = ready_asset

    get api_lecture_video_playback_url(@lecture), headers: authorization(token)

    assert_response :success
    body = response.parsed_body.fetch("playback")
    assert_equal asset.id, body.fetch("video_asset_id")
    assert_includes body.fetch("qualities").keys, "720p"
    assert_includes body.dig("qualities", "720p"), "/api/video_delivery/"
    assert_equal 0, body.fetch("last_position_seconds")
    assert_equal 0, body.fetch("watched_seconds")
    assert_equal student.user.name, body.dig("watermark", "name")

    patch api_lecture_watch_event_url(body.fetch("watch_event_id")),
      params: { position_seconds: 95, watched_seconds_delta: 95 }, headers: authorization(token), as: :json
    assert_response :success
    assert_nil response.parsed_body.dig("watch_event", "completed_at")
    assert_equal 0, response.parsed_body.dig("watch_event", "verified_watched_seconds")

    heartbeat_base = Time.current
    7.times do |index|
      travel_to heartbeat_base + ((index + 1) * 15).seconds do
        patch api_lecture_watch_event_url(body.fetch("watch_event_id")),
          params: { position_seconds: 95, watched_seconds_delta: 15 }, headers: authorization(token), as: :json
      end
    end

    assert response.parsed_body.dig("watch_event", "completed_at").present?
    assert_operator response.parsed_body.dig("watch_event", "verified_watched_seconds"), :>=, 90
  end

  test "student without lesson access cannot play video" do
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: @year, grade: @grade, status: :active, enrolled_at: Time.current)
    device = student.device_registrations.create!(device_fingerprint_digest: Security::DigestValue.call(SecureRandom.hex(8)), status: :active)
    token = Sessions::Start.call(user: student.user, device_registration: device).raw_token
    ready_asset

    get api_lecture_video_playback_url(@lecture), headers: authorization(token)

    assert_response :forbidden
  end

  test "assistant with video permission can preview playback" do
    assistant = create_user(role: :assistant)
    profile = AssistantProfile.create!(user: assistant)
    profile.assistant_permissions.create!(permission_key: "upload_videos", enabled: true)
    token = Sessions::Start.call(user: assistant).raw_token
    asset = ready_asset

    get api_lecture_video_playback_url(@lecture), headers: authorization(token)

    assert_response :success
    assert_equal asset.id, response.parsed_body.dig("playback", "video_asset_id")
    assert_nil response.parsed_body.dig("playback", "watermark")
  end

  test "assistant without content or video permission cannot preview playback" do
    assistant = create_user(role: :assistant)
    AssistantProfile.create!(user: assistant)
    token = Sessions::Start.call(user: assistant).raw_token
    ready_asset

    get api_lecture_video_playback_url(@lecture), headers: authorization(token)

    assert_response :forbidden
  end

  test "teacher attaches a YouTube video and student plays it inside the platform" do
    _student, token = enrolled_student_with_access
    post youtube_api_lecture_video_upload_url(@lecture), params: { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }, headers: authorization(@teacher_token), as: :json
    assert_response :success

    get api_lecture_video_playback_url(@lecture), headers: authorization(token)
    assert_response :success
    assert_equal "youtube", response.parsed_body.dig("playback", "source_type")
    assert_equal "dQw4w9WgXcQ", response.parsed_body.dig("playback", "youtube_video_id")
    assert_empty response.parsed_body.dig("playback", "qualities")
  end

  test "teacher reuses an existing processed video without uploading it again" do
    _student, token = enrolled_student_with_access
    source_asset = ready_asset
    another_lecture = Lecture.create!(lesson: @lesson, title: "Reused Lecture", position: 2, status: :published)

    post reuse_api_lecture_video_upload_url(another_lecture), params: { video_asset_id: source_asset.id }, headers: authorization(@teacher_token), as: :json
    assert_response :success
    assert_equal source_asset.id, another_lecture.reload.selected_video_asset_id

    get api_lecture_video_playback_url(another_lecture), headers: authorization(token)
    assert_response :success
    assert_equal source_asset.id, response.parsed_body.dig("playback", "video_asset_id")
  end

  test "delivery rejects an expired or invalid token" do
    asset = ready_asset

    get api_video_delivery_url(video_asset_id: asset.id, token: "invalid.token", path: "720p/index.m3u8")

    assert_response :unauthorized
  end

  test "development delivery caches remote video files" do
    asset = ready_asset
    variant = asset.video_variants.find_by!(quality: "720p")
    cache = Videos::Storage.delivery_cache
    cache.delete(variant.file_key)
    remote = Object.new
    remote.define_singleton_method(:local?) { false }
    remote.define_singleton_method(:read) { |_key| "#EXTM3U\n#EXTINF:6,\nsegment_00001.ts\n" }
    token = Videos::PlaybackToken.issue(video_asset: asset, viewer: @teacher)
    original_build = Videos::Storage.method(:build)
    Videos::Storage.define_singleton_method(:build) { remote }

    get api_video_delivery_url(
      video_asset_id: asset.id,
      token:,
      path: "720p/index.m3u8"
    )

    assert_response :success
    assert cache.exist?(variant.file_key)
    assert_equal "#EXTM3U\n#EXTINF:6,\nsegment_00001.ts\n", cache.read(variant.file_key)
    assert_includes response.body, "/api/video_delivery/#{asset.id}/"
    assert_includes response.body, "/720p/segment_00001.ts"
    refute_match(/^segment_00001\.ts$/, response.body)
  ensure
    Videos::Storage.define_singleton_method(:build, original_build) if defined?(original_build)
    cache&.delete(variant&.file_key) if defined?(cache)
  end

  private

  def enrolled_student_with_access
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: @year, grade: @grade, status: :active, enrolled_at: Time.current)
    LessonAccessGrant.create!(student_profile: student, lesson: @lesson, academic_year: @year, source: :manual, expires_on: @year.ends_on, status: :active)
    device = student.device_registrations.create!(device_fingerprint_digest: Security::DigestValue.call(SecureRandom.hex(8)), status: :active)
    [ student, Sessions::Start.call(user: student.user, device_registration: device).raw_token ]
  end

  def ready_asset
    prefix = "videos/#{SecureRandom.uuid}"
    @prefixes << prefix
    asset = VideoAsset.create!(
      lecture: @lecture, original_file_key: "#{prefix}/original/source.mp4",
      processing_status: :ready, duration_seconds: 100, available_qualities: [ "720p" ], created_by_user: @teacher
    )
    asset.video_variants.create!(quality: "720p", file_key: "#{prefix}/hls/720p/index.m3u8", status: :ready, size_bytes: 100)
    Videos::Storage.build.put("#{prefix}/hls/720p/index.m3u8", StringIO.new("#EXTM3U\n#EXTINF:6,\nsegment_00001.ts\n"))
    Videos::Storage.build.put("#{prefix}/hls/720p/segment_00001.ts", StringIO.new("segment"))
    asset
  end

  def authorization(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
