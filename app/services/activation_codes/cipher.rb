module ActivationCodes
  class Cipher
    def self.encrypt(raw_code)
      encryptor.encrypt_and_sign(raw_code)
    end

    def self.decrypt(ciphertext)
      encryptor.decrypt_and_verify(ciphertext)
    end

    def self.encryptor
      @encryptor ||= begin
        secret = Rails.application.secret_key_base
        key = ActiveSupport::KeyGenerator.new(secret).generate_key("activation-codes", ActiveSupport::MessageEncryptor.key_len)
        ActiveSupport::MessageEncryptor.new(key)
      end
    end

    private_class_method :encryptor
  end
end
