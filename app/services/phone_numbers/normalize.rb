module PhoneNumbers
  class Normalize < ApplicationService
    EGYPTIAN_MOBILE_FORMAT = /\A01[0125]\d{8}\z/
    E164_FORMAT = /\A\+[1-9]\d{7,14}\z/

    def self.call(value)
      new(value).call
    end

    def initialize(value)
      @value = value.to_s.strip
    end

    def call
      compact = @value.gsub(/[\s()-]/, "")
      normalized = normalize_egyptian_mobile(compact)
      return normalized if normalized.match?(E164_FORMAT)

      raise Error, "Phone number is invalid"
    end

    private

    def normalize_egyptian_mobile(value)
      return "+2#{value}" if value.match?(EGYPTIAN_MOBILE_FORMAT)
      return "+#{value}" if value.start_with?("201")

      value
    end
  end
end
