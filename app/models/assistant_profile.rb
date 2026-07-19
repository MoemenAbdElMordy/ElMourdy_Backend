class AssistantProfile < ApplicationRecord
  belongs_to :user
  has_many :assistant_permissions, dependent: :destroy

  validates :title, length: { maximum: 255 }, allow_blank: true
  validate :user_has_assistant_role

  private

  def user_has_assistant_role
    errors.add(:user, "must have the assistant role") if user && !user.assistant?
  end
end
