module Publishable
  extend ActiveSupport::Concern

  included do
    enum :status, { draft: 0, published: 1, hidden: 2, archived: 3 }, validate: true
    scope :visible, lambda {
      relation = published
      column_names.include?("publish_at") ? relation.where("publish_at IS NULL OR publish_at <= ?", Time.current) : relation
    }
    scope :ordered, -> { order(:position) }
  end
end
