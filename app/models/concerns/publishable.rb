module Publishable
  extend ActiveSupport::Concern

  included do
    enum :status, { draft: 0, published: 1, hidden: 2, archived: 3 }, validate: true
    scope :visible, -> { published.where("publish_at IS NULL OR publish_at <= ?", Time.current) }
    scope :ordered, -> { order(:position) }
  end
end
