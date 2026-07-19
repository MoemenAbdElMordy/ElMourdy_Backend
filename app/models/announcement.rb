class Announcement < ApplicationRecord
  enum :status, { draft: 0, published: 1, archived: 2 }, validate: true

  belongs_to :created_by_user, class_name: "User", optional: true
  has_many :announcement_targets, dependent: :destroy

  validates :title, :body, presence: true

  scope :visible, -> { published.where("publish_at IS NULL OR publish_at <= ?", Time.current) }
end
