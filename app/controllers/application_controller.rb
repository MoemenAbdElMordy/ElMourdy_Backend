class ApplicationController < ActionController::API
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable_entity
  rescue_from ApplicationService::Error, with: :render_unprocessable_entity

  private

  attr_reader :current_session, :current_user

  def authenticate_user!
    raw_token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    digest = Security::DigestValue.call(raw_token) if raw_token.present?
    @current_session = UserSession.active.includes(:user).find_by(session_token_digest: digest)
    @current_user = @current_session&.user

    return render_unauthorized unless @current_session && @current_user&.active?

    @current_session.update_column(:last_seen_at, Time.current)
  end

  def render_unauthorized
    render json: { error: { code: "unauthorized", message: "Authentication is required" } },
      status: :unauthorized
  end

  def render_bad_request(error)
    render json: { error: { code: "bad_request", message: error.message } }, status: :bad_request
  end

  def render_unprocessable_entity(error)
    messages = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
    render json: {
      error: { code: "unprocessable_entity", message: "The request could not be processed", details: messages }
    }, status: :unprocessable_entity
  end
end
