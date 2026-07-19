class Chapter < ApplicationRecord
  include Publishable

  belongs_to :branch
  has_many :lessons, dependent: :restrict_with_error
  has_many :exams, dependent: :restrict_with_error

  validates :title, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :branch_id }
end
