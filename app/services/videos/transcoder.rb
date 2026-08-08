require "open3"

module Videos
  class Transcoder
    QUALITIES = {
      "360p" => { width: 640, height: 360, video_bitrate: "600k", maxrate: "700k", buffer: "1200k", audio_bitrate: "96k" },
      "480p" => { width: 854, height: 480, video_bitrate: "1000k", maxrate: "1150k", buffer: "2000k", audio_bitrate: "96k" },
      "720p" => { width: 1280, height: 720, video_bitrate: "1800k", maxrate: "2100k", buffer: "3600k", audio_bitrate: "128k" }
    }.freeze

    def initialize(input:, output_root:)
      @input = input
      @output_root = output_root
    end

    def call
      duration = probe_duration
      QUALITIES.each { |quality, settings| transcode(quality, settings) }
      duration
    end

    private

    def probe_duration
      output, error, status = Open3.capture3(
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", @input.to_s
      )
      raise "FFprobe failed: #{error.strip}" unless status.success?

      output.to_f.ceil
    end

    def transcode(quality, settings)
      directory = @output_root.join(quality)
      FileUtils.mkdir_p(directory)
      command = [
        "ffmpeg", "-y", "-i", @input.to_s,
        "-vf", "scale=#{settings[:width]}:#{settings[:height]}:force_original_aspect_ratio=decrease:force_divisible_by=2",
        "-c:v", "libx264", "-preset", "veryfast",
        "-b:v", settings[:video_bitrate], "-maxrate", settings[:maxrate], "-bufsize", settings[:buffer],
        "-c:a", "aac", "-b:a", settings[:audio_bitrate], "-ac", "2",
        "-hls_time", "6", "-hls_playlist_type", "vod", "-hls_flags", "independent_segments",
        "-hls_segment_filename", directory.join("segment_%05d.ts").to_s,
        directory.join("index.m3u8").to_s
      ]
      _output, error, status = Open3.capture3(*command)
      raise "FFmpeg failed for #{quality}: #{error.lines.last(10).join}" unless status.success?
    end
  end
end
