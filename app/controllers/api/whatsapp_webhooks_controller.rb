module Api
  class WhatsappWebhooksController < ApplicationController
    def show
      return head :forbidden unless valid_subscription_request?

      render plain: params["hub.challenge"]
    end

    def create
      return head :unauthorized unless valid_signature?

      inbound_messages.each do |message|
        sender = message["from"].to_s
        next if sender.blank?

        WhatsappVerifications::Confirm.call(
          phone: "+#{sender}",
          message: message.dig("text", "body"),
          message_id: message["id"]
        )
      end

      head :no_content
    end

    private

    def valid_subscription_request?
      params["hub.mode"] == "subscribe" &&
        ActiveSupport::SecurityUtils.secure_compare(
          params["hub.verify_token"].to_s,
          ENV.fetch("WHATSAPP_WEBHOOK_VERIFY_TOKEN")
        )
    end

    def valid_signature?
      provided = request.headers["X-Hub-Signature-256"].to_s
      expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("META_APP_SECRET"), request.raw_post)}"

      provided.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end

    def inbound_messages
      Array(params[:entry]).flat_map do |entry|
        Array(entry[:changes]).flat_map do |change|
          Array(change.dig(:value, :messages)).select { |message| message[:type] == "text" }
        end
      end
    end
  end
end
