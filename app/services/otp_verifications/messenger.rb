module OtpVerifications
  class Messenger
    def self.build
      return DevelopmentSender.new if ENV.fetch("OTP_DELIVERY_METHOD", default_method) == "development"

      Whatsapp::Client.new
    end

    def self.default_method
      Rails.env.production? ? "whatsapp" : "development"
    end

    private_class_method :default_method
  end
end
