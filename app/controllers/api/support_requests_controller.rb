module Api
  class SupportRequestsController < ApplicationController
    before_action :authenticate_user!

    def index
      requests = if current_user.teacher? || current_user.assistant?
        require_teacher_or_assistant_permission!("manage_support_requests")
        return if performed?

        SupportRequest.all
      else
        current_user.support_requests
      end
      render json: { support_requests: requests.includes(:requester_user, :student_profile, :support_request_actions).order(created_at: :desc).map { |record| serialize(record) } }
    end

    def show
      record = SupportRequest.find(params[:id])
      return render_forbidden unless can_view?(record)

      render json: { support_request: serialize(record) }
    end

    def create
      student_profile = current_user.student? ? current_user.student_profile : linked_student
      record = current_user.support_requests.create!(support_request_params.merge(student_profile:))
      render json: { support_request: serialize(record) }, status: :created
    end

    def review
      require_teacher_or_assistant_permission!("manage_support_requests")
      return if performed?

      record = SupportRequest.find(params[:id])
      decision = params.require(:decision)
      raise ActionController::ParameterMissing, :decision unless %w[approve reject].include?(decision)

      SupportRequest.transaction do
        record.lock!
        raise ApplicationService::Error, "This support request has already been reviewed" unless record.pending?

        record.support_request_actions.create!(
          reviewer_user: current_user, action: decision, note: params[:note]
        )
        record.update!(status: decision == "approve" ? :approved : :rejected)
      end
      render json: { support_request: serialize(record.reload) }
    end

    private

    def support_request_params
      params.require(:support_request).permit(:request_type, :reason, :student_profile_id, payload: {})
    end

    def linked_student
      return unless current_user.parent? && support_request_params[:student_profile_id].present?

      current_user.parent_profile.student_profiles.find(support_request_params[:student_profile_id])
    end

    def can_view?(record)
      return record.requester_user_id == current_user.id unless current_user.teacher? || current_user.assistant?

      require_teacher_or_assistant_permission!("manage_support_requests")
      !performed?
    end

    def serialize(record)
      {
        id: record.id, request_type: record.request_type, status: record.status, reason: record.reason,
        payload: record.payload || {}, student_profile_id: record.student_profile_id,
        requester: { id: record.requester_user.id, name: record.requester_user.name, role: record.requester_user.role },
        created_at: record.created_at,
        actions: record.support_request_actions.order(:created_at).map do |action|
          { action: action.action, note: action.note, reviewer_user_id: action.reviewer_user_id, created_at: action.created_at }
        end
      }
    end
  end
end
