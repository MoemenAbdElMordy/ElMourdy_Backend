class AddExpectedSizeToVideoAssets < ActiveRecord::Migration[8.0]
  def change
    add_column :video_assets, :expected_size_bytes, :bigint
  end
end
