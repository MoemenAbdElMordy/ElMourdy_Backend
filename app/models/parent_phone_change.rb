class ParentPhoneChange < ApplicationRecord
  include E164Phone

  enum :status, { pending_otp: 0, verified: 1, applied: 2, cancelled: 3 }, validate: true

  belongs_to :student_profile
  belongs_to :requested_by_user, class_name: "User"
  belongs_to :otp_verification, optional: true

  validates :old_phone_e164, :new_phone_e164, presence: true
  validates_e164_phone :old_phone_e164, :new_phone_e164
  validate :phone_actually_changes

  private

  def phone_actually_changes
    errors.add(:new_phone_e164, "must differ from the current phone") if old_phone_e164 == new_phone_e164
  end
end
