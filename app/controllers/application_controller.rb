class ApplicationController < ActionController::API
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable_entity
  rescue_from ApplicationService::Error, with: :render_unprocessable_entity

  private

  attr_reader :current_session, :current_user

  def authenticate_user!
    raw_token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    digest = Security::DigestValue.call(raw_token) if raw_token.present?
    @current_session = UserSession.active.includes(:user).find_by(session_token_digest: digest)
    end_stale_session
    @current_user = @current_session&.user

    return render_unauthorized unless @current_session && @current_user&.active?

    now = Time.current
    @current_session.update_column(:last_seen_at, now)
    @current_session.device_registration&.update_column(:last_seen_at, now)
  end

  def render_unauthorized
    render json: { error: { code: "unauthorized", message: "Authentication is required" } },
      status: :unauthorized
  end

  def end_stale_session
    return unless @current_session&.stale?

    @current_session.update!(status: :ended, ended_at: Time.current)
    @current_session = nil
  end

  def require_role!(*roles)
    return if roles.any? { |role| current_user.public_send("#{role}?") }

    render_forbidden
  end

  def require_teacher!
    require_role!(:teacher)
  end

  def require_assistant_permission!(permission_key)
    return if current_user.teacher?
    return render_forbidden unless current_user.assistant?

    permissions = current_user.assistant_profile&.assistant_permissions
    allowed = permissions&.where(enabled: true)&.exists?(permission_key:)
    render_forbidden unless allowed
  end

  def serialize_user(user)
    {
      id: user.id,
      name: user.name,
      phone: user.phone_e164,
      role: user.role,
      permissions: assistant_permissions(user)
    }
  end

  def assistant_permissions(user)
    return [] unless user.assistant?

    user.assistant_profile&.assistant_permissions&.where(enabled: true)&.pluck(:permission_key) || []
  end

  def render_bad_request(error)
    render json: { error: { code: "bad_request", message: error.message } }, status: :bad_request
  end

  def render_not_found
    render json: { error: { code: "not_found", message: "The requested resource was not found" } },
      status: :not_found
  end

  def render_forbidden
    render json: { error: { code: "forbidden", message: "You do not have permission to perform this action" } },
      status: :forbidden
  end

  def render_unprocessable_entity(error)
    messages = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
    render json: {
      error: { code: "unprocessable_entity", message: "The request could not be processed", details: messages }
    }, status: :unprocessable_entity
  end
end
