class ParentProfile < ApplicationRecord
  include E164Phone

  belongs_to :user
  has_many :student_parent_links, dependent: :restrict_with_error
  has_many :student_profiles, through: :student_parent_links

  validates :verified_parent_phone_e164, presence: true
  validates_e164_phone :verified_parent_phone_e164
  validate :user_has_parent_role

  private

  def user_has_parent_role
    errors.add(:user, "must have the parent role") if user && !user.parent?
  end
end
