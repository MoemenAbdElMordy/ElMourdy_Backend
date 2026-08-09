require "open3"

module Videos
  class Transcoder
    QUALITY_ORDER = %w[480p 720p 360p].freeze
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
      QUALITY_ORDER.each do |quality|
        transcode(quality, QUALITIES.fetch(quality))
        yield quality, duration if block_given?
      end
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
        *encoder_options,
        "-b:v", settings[:video_bitrate], "-maxrate", settings[:maxrate], "-bufsize", settings[:buffer],
        "-c:a", "aac", "-b:a", settings[:audio_bitrate], "-ac", "2",
        "-hls_time", "6", "-hls_playlist_type", "vod", "-hls_flags", "independent_segments",
        "-hls_segment_filename", directory.join("segment_%05d.ts").to_s,
        directory.join("index.m3u8").to_s
      ]
      _output, error, status = Open3.capture3(*command)
      raise "FFmpeg failed for #{quality}: #{error.lines.last(10).join}" unless status.success?
    end

    def encoder_options
      hardware_encoder? ? [ "-c:v", "h264_nvenc", "-preset", "p4", "-tune", "hq", "-rc", "vbr" ] :
        [ "-c:v", "libx264", "-preset", "veryfast" ]
    end

    def hardware_encoder?
      return @hardware_encoder if defined?(@hardware_encoder)

      requested = ENV.fetch("VIDEO_ENCODER", "auto")
      @hardware_encoder = requested == "nvenc" || (requested == "auto" && Gem.win_platform? && nvenc_available?)
    end

    def nvenc_available?
      _output, _error, status = Open3.capture3(
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=size=640x360:rate=1",
        "-frames:v", "1", "-c:v", "h264_nvenc", "-f", "null", "-"
      )
      status.success?
    end
  end
end
