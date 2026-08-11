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
      render json: {
        support_requests: requests.includes(:requester_user, :student_profile,
          support_request_actions: :reviewer_user).order(created_at: :desc).map { |record| serialize(record) }
      }
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
      require_review_permission!(record)
      return if performed?
      decision = params.require(:decision)
      raise ActionController::ParameterMissing, :decision unless %w[approve reject].include?(decision)

      SupportRequest.transaction do
        record.lock!
        raise ApplicationService::Error, "This support request has already been reviewed" unless record.pending?

        record.support_request_actions.create!(
          reviewer_user: current_user, action: decision, note: params[:note]
        )
        apply_approval!(record) if decision == "approve"
        record.update!(status: decision == "approve" ? :approved : :rejected)
      end
      audit!(action: "support_request.#{decision}d", target: record,
        metadata: { request_type: record.request_type })
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

    def apply_approval!(record)
      if record.device_removal?
        remove_requested_device!(record)
      elsif record.parent_phone_change?
        change_parent_phone!(record)
      end
    end

    def require_review_permission!(record)
      permission = if record.device_removal?
        "manage_devices"
      elsif record.extra_exam_attempt?
        "manage_exams"
      else
        "manage_parent_phone"
      end
      require_teacher_or_assistant_permission!(permission)
    end

    def remove_requested_device!(record)
      payload = record.payload.to_h
      device_id = payload["device_registration_id"] || payload[:device_registration_id] ||
        payload["device_id"] || payload[:device_id]
      raise ApplicationService::Error, "The device was not supplied" if device_id.blank?

      device = record.student_profile.device_registrations.find(device_id)
      device.update!(status: :removed, removed_at: Time.current)
      device.user_sessions.active.update_all(status: UserSession.statuses[:revoked], ended_at: Time.current)
    end

    def change_parent_phone!(record)
      new_phone = PhoneNumbers::Normalize.call(record.payload.to_h["new_parent_phone"])
      profile = record.student_profile
      raise ApplicationService::Error, "The student profile was not supplied" unless profile
      raise ApplicationService::Error, "The parent phone must differ from the student phone" if new_phone == profile.user.phone_e164

      profile.update!(parent_phone_e164: new_phone)
      profile.student_parent_links.active.joins(:parent_profile)
        .where.not(parent_profiles: { verified_parent_phone_e164: new_phone })
        .update_all(status: StudentParentLink.statuses[:removed], updated_at: Time.current)
      ParentProfile.where(verified_parent_phone_e164: new_phone).find_each do |parent_profile|
        link = profile.student_parent_links.find_or_initialize_by(parent_profile:)
        link.update!(status: :active, relation: link.relation || :other, linked_at: Time.current)
      end
    end

    def serialize(record)
      {
        id: record.id, request_type: record.request_type, status: record.status, reason: record.reason,
        payload: record.payload || {}, student_profile_id: record.student_profile_id,
        requester: { id: record.requester_user.id, name: record.requester_user.name, role: record.requester_user.role },
        created_at: record.created_at,
        actions: record.support_request_actions.order(:created_at).map do |action|
          {
            action: action.action, note: action.note, reviewer_user_id: action.reviewer_user_id,
            reviewer_name: action.reviewer_user.name, created_at: action.created_at
          }
        end
      }
    end
  end
end
