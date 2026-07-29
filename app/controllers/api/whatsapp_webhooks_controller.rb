module Api
  class WhatsappWebhooksController < ApplicationController
    def show
      return head :forbidden unless valid_subscription_request?

      render plain: params["hub.challenge"]
    end

    def create
      return head :unauthorized unless valid_signature?

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
  end
end
