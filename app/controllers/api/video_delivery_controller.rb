module Api
  class VideoDeliveryController < ApplicationController
    def show
      asset = VideoAsset.find(params[:video_asset_id])
      payload = Videos::PlaybackToken.verify(params[:token], video_asset: asset)
      return render_unauthorized unless payload

      match = /\A(360p|480p|720p)\/(index\.m3u8|segment_\d{5}\.ts)\z/.match(params[:path].to_s)
      return render_bad_path unless match

      relative_path = "#{match[1]}/#{match[2]}"
      key = "#{payload[:prefix]}/#{relative_path}"
      storage = Videos::Storage.build
      cache = Videos::Storage.delivery_cache
      if Rails.env.local? && cache.exist?(key)
        send_data cache.read(key), type: content_type(Pathname(key)), disposition: "inline"
      elsif storage.local?
        return render_not_found unless storage.exist?(key)

        send_data storage.read(key), type: content_type(Pathname(key)), disposition: "inline"
      elsif Rails.env.local?
        data = storage.read(key)
        cache.put(key, StringIO.new(data))
        send_data data, type: content_type(Pathname(key)), disposition: "inline"
      else
        redirect_to storage.presigned_get(key), allow_other_host: true
      end
    end

    private

    def content_type(path)
      path.extname == ".m3u8" ? "application/vnd.apple.mpegurl" : "video/mp2t"
    end

    def render_bad_path
      render json: { error: { code: "bad_request", message: "Invalid video path" } }, status: :bad_request
    end
  end
end
