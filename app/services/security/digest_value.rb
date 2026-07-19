module Security
  class DigestValue
    def self.call(value, pepper: ENV.fetch("SECURITY_PEPPER"))
      OpenSSL::HMAC.hexdigest("SHA256", pepper, value.to_s)
    end
  end
end
