require "base64"
require "json"
require "openssl"

module Videos
  class PlaybackToken
    DEFAULT_TTL = 15.minutes

    def self.issue(video_asset:, viewer:, ttl: DEFAULT_TTL)
      payload = {
        asset_id: video_asset.id,
        viewer_id: viewer.id,
        prefix: "#{File.dirname(File.dirname(video_asset.original_file_key))}/hls",
        expires_at: ttl.from_now.to_i
      }
      encoded = Base64.urlsafe_encode64(payload.to_json, padding: false)
      "#{encoded}.#{signature(encoded)}"
    end

    def self.verify(token, video_asset:)
      encoded, supplied_signature = token.to_s.split(".", 2)
      return unless encoded.present? && supplied_signature.present?
      return unless ActiveSupport::SecurityUtils.secure_compare(signature(encoded), supplied_signature)

      payload = JSON.parse(Base64.urlsafe_decode64(encoded)).with_indifferent_access
      return if payload[:asset_id].to_i != video_asset.id || payload[:expires_at].to_i < Time.current.to_i

      payload
    rescue ArgumentError, JSON::ParserError
      nil
    end

    def self.signature(encoded)
      OpenSSL::HMAC.hexdigest("SHA256", secret, encoded)
    end
    private_class_method :signature

    def self.secret
      ENV["VIDEO_PLAYBACK_SECRET"].presence || Rails.application.secret_key_base
    end
    private_class_method :secret
  end
end
