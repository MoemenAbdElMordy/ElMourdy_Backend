class SupportRequestAction < ApplicationRecord
  enum :action, { approve: 0, reject: 1, comment: 2 }, prefix: true, validate: true

  belongs_to :support_request
  belongs_to :reviewer_user, class_name: "User"

  validates :note, presence: true, if: :action_comment?
end
