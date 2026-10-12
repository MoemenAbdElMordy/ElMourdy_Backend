module TelegramGateway
  def self.enabled?
    ENV["TELEGRAM_GATEWAY_ENABLED"] == "true" && ENV["TELEGRAM_GATEWAY_TOKEN"].present?
  end
end
