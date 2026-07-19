class StudentProfile < ApplicationRecord
  include E164Phone

  belongs_to :user
  has_many :student_parent_links, dependent: :restrict_with_error
  has_many :parent_profiles, through: :student_parent_links
  has_many :student_enrollments, dependent: :restrict_with_error
  has_many :lesson_access_grants, dependent: :restrict_with_error
  has_many :exam_attempts, dependent: :restrict_with_error
  has_many :device_registrations, dependent: :restrict_with_error
  has_many :lecture_watch_events, dependent: :restrict_with_error
  has_many :support_requests, dependent: :restrict_with_error
  has_many :parent_phone_changes, dependent: :restrict_with_error

  validates :birth_date, presence: true
  validates :parent_phone_e164, presence: true
  validates_e164_phone :parent_phone_e164
  validate :user_has_student_role

  private

  def user_has_student_role
    errors.add(:user, "must have the student role") if user && !user.student?
  end
end
