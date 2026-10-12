class ActivationCodeBatch < ApplicationRecord
  belongs_to :lesson, optional: true
  belongs_to :academic_year, optional: true
  belongs_to :grade, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true
  has_many :activation_codes, dependent: :restrict_with_error

  validates :name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 500 }
  validates :expires_on, presence: true
  validate :expiration_is_in_the_future, on: :create

  scope :available, -> { where(deleted_at: nil).where("expires_on >= ?", Date.current) }

  def archived?
    deleted_at.present?
  end

  def generic?
    lesson_id.nil?
  end

  private

  def expiration_is_in_the_future
    errors.add(:expires_on, "must be today or later") if expires_on && expires_on < Date.current
  end
end
