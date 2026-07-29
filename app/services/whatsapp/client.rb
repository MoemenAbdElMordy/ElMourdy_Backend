require "net/http"

module Whatsapp
  class Client < ApplicationService
    class DeliveryError < Error; end

    def initialize(
      access_token: ENV.fetch("WHATSAPP_ACCESS_TOKEN"),
      phone_number_id: ENV.fetch("WHATSAPP_PHONE_NUMBER_ID"),
      api_version: ENV.fetch("WHATSAPP_GRAPH_API_VERSION", "v25.0")
    )
      @access_token = access_token
      @phone_number_id = phone_number_id
      @api_version = api_version
    end

    def send_otp(phone:, code:)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(build_request(phone:, code:))
      end

      body = JSON.parse(response.body)
      raise DeliveryError, "WhatsApp could not deliver the verification code" unless response.is_a?(Net::HTTPSuccess)

      body.dig("messages", 0, "id")
    rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error
      raise DeliveryError, "WhatsApp could not deliver the verification code"
    end

    private

    def uri
      URI("https://graph.facebook.com/#{@api_version}/#{@phone_number_id}/messages")
    end

    def build_request(phone:, code:)
      Net::HTTP::Post.new(uri).tap do |request|
        request["Authorization"] = "Bearer #{@access_token}"
        request["Content-Type"] = "application/json"
        request.body = request_body(phone:, code:).to_json
      end
    end

    def request_body(phone:, code:)
      {
        messaging_product: "whatsapp",
        to: phone.delete_prefix("+"),
        type: "template",
        template: {
          name: ENV.fetch("WHATSAPP_OTP_TEMPLATE_NAME"),
          language: { code: ENV.fetch("WHATSAPP_OTP_TEMPLATE_LANGUAGE", "en") },
          components: [
            {
              type: "body",
              parameters: [ { type: "text", text: code } ]
            },
            {
              type: "button",
              sub_type: "url",
              index: "0",
              parameters: [ { type: "text", text: code } ]
            }
          ]
        }
      }
    end
  end
end
