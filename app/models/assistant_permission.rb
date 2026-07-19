class AssistantPermission < ApplicationRecord
  KEYS = %w[
    manage_students manage_parent_phone manage_devices manage_support_requests
    manage_content upload_videos manage_exams manage_codes manage_announcements
    view_reports manage_academic_years
  ].freeze

  belongs_to :assistant_profile

  validates :permission_key, presence: true, inclusion: { in: KEYS },
    uniqueness: { scope: :assistant_profile_id }
end
