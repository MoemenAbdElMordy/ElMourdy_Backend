class CacheVersions
  def self.current(namespace)
    Rails.cache.fetch("cache-version/#{namespace}") { SecureRandom.uuid }
  end

  def self.bump(namespace)
    Rails.cache.write("cache-version/#{namespace}", SecureRandom.uuid)
  end
end
