require "test_helper"

class IndexDesignTest < ActiveSupport::TestCase
  test "non-unique indexes are not redundant left prefixes" do
    redundant = ActiveRecord::Base.connection.tables.flat_map do |table|
      redundant_indexes_for(table)
    end

    assert_empty redundant, "Redundant indexes found: #{redundant.join(', ')}"
  end

  private

  def redundant_indexes_for(table)
    indexes = ActiveRecord::Base.connection.indexes(table)
    indexes.combination(2).flat_map do |first, second|
      [ [ first, second ], [ second, first ] ].filter_map do |short, long|
        next if short.unique
        next unless short.columns == long.columns.first(short.columns.length)

        "#{table}.#{short.name} is covered by #{long.name}"
      end
    end
  end
end
