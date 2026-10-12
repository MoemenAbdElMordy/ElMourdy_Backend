require "net/http"

module TelegramGateway
  class Client < ApplicationService
    class DeliveryError < Error; end

    ENDPOINT = URI("https://gatewayapi.telegram.org/sendVerificationMessage")

    def initialize(token: ENV["TELEGRAM_GATEWAY_TOKEN"])
      @token = token.to_s
    end

    def send_code(phone:, code:, ttl:)
      raise DeliveryError, "Telegram verification is not configured" if @token.blank?

      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{@token}"
      request["Content-Type"] = "application/json"
      request.body = { phone_number: phone, code:, ttl: }.to_json

      response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true,
        open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      body = JSON.parse(response.body)
      raise DeliveryError, "Telegram could not deliver the verification code" unless
        response.is_a?(Net::HTTPSuccess) && body["ok"] && body.dig("result", "request_id").present?

      body.fetch("result").fetch("request_id")
    rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error
      raise DeliveryError, "Telegram could not deliver the verification code"
    end
  end
end
