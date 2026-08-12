require "test_helper"

class CacheVersionsTest < ActiveSupport::TestCase
  test "bumping a namespace invalidates keys built with the previous version" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    first_version = CacheVersions.current("catalog")
    Rails.cache.write("catalog/#{first_version}/resource", "cached")
    CacheVersions.bump("catalog")

    assert_not_equal first_version, CacheVersions.current("catalog")
    assert_equal "cached", Rails.cache.read("catalog/#{first_version}/resource")
    assert_nil Rails.cache.read("catalog/#{CacheVersions.current('catalog')}/resource")
  ensure
    Rails.cache = previous_cache
  end
end
