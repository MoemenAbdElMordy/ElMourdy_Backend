module ActivationCodes
  class GenerateBatch < ApplicationService
    Result = Data.define(:batch, :raw_codes)

    def self.call(attributes:, created_by_user:)
      new(attributes:, created_by_user:).call
    end

    def initialize(attributes:, created_by_user:)
      @attributes = attributes
      @created_by_user = created_by_user
    end

    def call
      raw_codes = []
      batch = ActivationCodeBatch.transaction do
        record = ActivationCodeBatch.create!(@attributes.merge(created_by_user: @created_by_user))
        record.quantity.times do
          raw_code = unique_code
          record.activation_codes.create!(
            code_digest: Security::DigestValue.call(raw_code),
            code_ciphertext: Cipher.encrypt(raw_code),
            status: :unused
          )
          raw_codes << raw_code
        end
        record
      end
      Result.new(batch:, raw_codes:)
    end

    private

    def unique_code
      loop do
        raw_code = "ELM-#{SecureRandom.alphanumeric(4).upcase}-#{SecureRandom.alphanumeric(4).upcase}"
        return raw_code unless ActivationCode.exists?(code_digest: Security::DigestValue.call(raw_code))
      end
    end
  end
end
