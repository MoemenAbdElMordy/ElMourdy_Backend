module Curriculum
  class Reorder < ApplicationService
    def self.call(scope:, ordered_ids:)
      new(scope:, ordered_ids:).call
    end

    def initialize(scope:, ordered_ids:)
      @scope = scope
      @ordered_ids = Array(ordered_ids).map(&:to_i)
    end

    def call
      records = scope.where(id: ordered_ids).index_by(&:id)
      raise Error, "The ordering list must contain every item exactly once" unless valid_order?(records)

      scope.model.transaction do
        temporary_offset = scope.maximum(:position).to_i
        records.each_value { |record| record.update_column(:position, temporary_offset + record.id) }
        ordered_ids.each_with_index { |id, index| records.fetch(id).update!(position: index + 1) }
      end
    end

    private

    attr_reader :scope, :ordered_ids

    def valid_order?(records)
      ordered_ids.uniq.length == ordered_ids.length && records.keys.sort == scope.pluck(:id).sort
    end
  end
end
