module Sessions
  class CleanupStale < ApplicationService
    def self.call(at: Time.current)
      new(at:).call
    end

    def initialize(at:)
      @at = at
    end

    def call
      UserSession.stale(@at).update_all(
        status: UserSession.statuses[:ended], ended_at: @at, updated_at: @at
      )
    end
  end
end
