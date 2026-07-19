class AuditLog < ApplicationRecord
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :target, polymorphic: true

  validates :action, presence: true

  def readonly?
    persisted?
  end
end
