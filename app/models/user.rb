class User < ApplicationRecord
  include E164Phone

  has_secure_password

  enum :role, { teacher: 0, assistant: 1, student: 2, parent: 3 }, validate: true
  enum :status, { active: 0, suspended: 1, archived: 2 }, validate: true

  has_one :student_profile, dependent: :restrict_with_error
  has_one :parent_profile, dependent: :restrict_with_error
  has_one :assistant_profile, dependent: :restrict_with_error
  has_many :user_sessions, dependent: :restrict_with_error
  has_many :otp_verifications, dependent: :nullify
  has_many :support_requests, foreign_key: :requester_user_id, inverse_of: :requester_user,
    dependent: :restrict_with_error
  has_many :audit_logs, foreign_key: :actor_user_id, inverse_of: :actor_user, dependent: :nullify

  validates :name, presence: true, length: { maximum: 255 }
  validates :phone_e164, presence: true, uniqueness: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true, allow_blank: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates_e164_phone :phone_e164

  scope :available_for_login, -> { active.where.not(phone_verified_at: nil) }
end
