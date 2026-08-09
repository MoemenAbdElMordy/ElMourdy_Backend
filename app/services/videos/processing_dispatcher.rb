require "rbconfig"

module Videos
  class ProcessingDispatcher
    def self.call(video_asset_id)
      if Rails.env.development? && Gem.win_platform?
        launch_windows_process(video_asset_id)
      else
        VideoProcessingJob.perform_later(video_asset_id)
      end
    end

    def self.launch_windows_process(video_asset_id)
      environment = { "VIDEO_ASSET_ID" => Integer(video_asset_id).to_s }
      command = [
        RbConfig.ruby,
        Rails.root.join("bin/rails").to_s,
        "runner",
        "VideoProcessingJob.perform_now(Integer(ENV.fetch('VIDEO_ASSET_ID')))"
      ]
      log_path = Rails.root.join("log/video-processing.log")
      File.open(log_path, "a") do |log|
        process_id = Process.spawn(environment, *command, chdir: Rails.root.to_s, out: log, err: log, new_pgroup: true)
        Process.detach(process_id)
      end
    end

    private_class_method :launch_windows_process
  end
end
