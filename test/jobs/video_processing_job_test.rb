require "test_helper"

class VideoProcessingJobTest < ActiveJob::TestCase
  setup do
    _year, _grade, _branch, _chapter, lesson = create_curriculum
    @lecture = Lecture.create!(lesson:, title: "Processing Test", position: 1, status: :published)
    @teacher = create_user(role: :teacher)
    @prefix = "videos/#{SecureRandom.uuid}"
    @asset = VideoAsset.create!(
      lecture: @lecture,
      original_file_key: "#{@prefix}/original/source.mp4",
      processing_status: :uploaded,
      created_by_user: @teacher
    )
    source = Videos::Storage.staging.path_for(@asset.original_file_key)
    FileUtils.mkdir_p(source.dirname)
    created = system(
      "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
      "-f", "lavfi", "-i", "color=c=black:s=320x180:r=24",
      "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
      "-t", "1", "-c:v", "libx264", "-c:a", "aac", source.to_s
    )
    raise "Could not create the video processing fixture" unless created
  end

  teardown do
    Videos::Storage.staging.delete_prefix(@prefix)
    Videos::Storage.build.delete_prefix(@prefix)
  end

  test "publishes each final quality and removes the staged original" do
    previous_encoder = ENV["VIDEO_ENCODER"]
    ENV["VIDEO_ENCODER"] = "cpu"
    begin
      VideoProcessingJob.perform_now(@asset.id)
    ensure
      ENV["VIDEO_ENCODER"] = previous_encoder
    end

    @asset.reload
    assert @asset.ready?
    assert_equal Videos::Transcoder::QUALITY_ORDER, @asset.available_qualities
    assert_equal 1, @asset.duration_seconds
    assert_equal 1, @lecture.reload.duration_seconds
    assert_equal %w[360p 480p 720p], @asset.video_variants.ready.order(:quality).pluck(:quality)
    assert_not Videos::Storage.staging.exist?(@asset.original_file_key)
    assert Videos::Storage.build.exist?("#{@prefix}/hls/480p/index.m3u8")
  end
end
