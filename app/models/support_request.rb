class SupportRequest < ApplicationRecord
  enum :request_type, { device_removal: 0, extra_exam_attempt: 1, parent_phone_change: 2 },
    validate: true
  enum :status, { pending: 0, approved: 1, rejected: 2, cancelled: 3 }, validate: true

  belongs_to :requester_user, class_name: "User"
  belongs_to :student_profile, optional: true
  has_many :support_request_actions, dependent: :destroy

  scope :work_queue, -> { pending.order(:created_at) }
end
