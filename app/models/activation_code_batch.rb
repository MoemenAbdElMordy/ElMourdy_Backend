class ActivationCodeBatch < ApplicationRecord
  belongs_to :lesson
  belongs_to :academic_year
  belongs_to :grade
  belongs_to :created_by_user, class_name: "User", optional: true
  has_many :activation_codes, dependent: :restrict_with_error

  validates :name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :expires_on, presence: true

  scope :available, -> { where(deleted_at: nil).where("expires_on >= ?", Date.current) }

  def archived?
    deleted_at.present?
  end
end
