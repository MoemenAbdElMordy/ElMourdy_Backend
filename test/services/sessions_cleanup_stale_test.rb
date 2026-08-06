require "test_helper"

class SessionsCleanupStaleTest < ActiveSupport::TestCase
  test "ends only stale active sessions" do
    user = create_parent.user
    stale_session = create_session(user, last_seen_at: 31.days.ago)
    recent_session = create_session(user, last_seen_at: 29.days.ago)

    assert_equal 1, Sessions::CleanupStale.call
    assert stale_session.reload.ended?
    assert recent_session.reload.active?
  end

  private

  def create_session(user, last_seen_at:)
    UserSession.create!(
      user:,
      session_token_digest: Security::DigestValue.call(SecureRandom.hex),
      status: :active,
      started_at: last_seen_at,
      last_seen_at:
    )
  end
end
