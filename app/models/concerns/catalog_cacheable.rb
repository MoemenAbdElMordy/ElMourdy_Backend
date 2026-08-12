module CatalogCacheable
  extend ActiveSupport::Concern

  included do
    after_commit -> { CacheVersions.bump("catalog") }
  end
end
