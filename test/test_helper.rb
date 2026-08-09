ENV["RAILS_ENV"] ||= "test"
ENV["SECURITY_PEPPER"] ||= "test-only-security-pepper"
ENV["VIDEO_STORAGE_SERVICE"] = "local"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/record_factory"

class ActiveSupport::TestCase
  include RecordFactory
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
