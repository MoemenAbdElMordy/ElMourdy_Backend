module E164Phone
  extend ActiveSupport::Concern

  E164_FORMAT = /\A\+[1-9]\d{7,14}\z/

  class_methods do
    def validates_e164_phone(*attributes)
      validates(*attributes, format: {
        with: E164_FORMAT,
        message: "must use E.164 format"
      })
    end
  end
end
