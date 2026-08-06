module OtpVerifications
  class DevelopmentSender
    attr_reader :last_code

    def send_otp(phone:, code:)
      raise Whatsapp::Client::DeliveryError, "Development OTP delivery is disabled" if Rails.env.production?

      @last_code = code
      Rails.logger.info("Development OTP generated for #{phone}")
      "development-#{SecureRandom.uuid}"
    end
  end
end
