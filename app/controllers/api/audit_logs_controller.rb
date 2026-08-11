module Api
  class AuditLogsController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("view_reports") }

    def index
      logs = AuditLog.joins(:actor_user).merge(User.assistant).includes(:actor_user).order(created_at: :desc)
      logs = logs.where(action: params[:event]) if params[:event].present?
      logs = logs.where(actor_user_id: params[:actor_user_id]) if params[:actor_user_id].present?
      logs = logs.limit(200)

      render json: {
        audit_logs: logs.map do |log|
          {
            id: log.id,
            description_key: action_description_key(log.action),
            section_key: action_section_key(log.action),
            assistant: { id: log.actor_user.id, name: log.actor_user.name },
            created_at: log.created_at
          }
        end
      }
    end

    private

    ACTION_DESCRIPTION_KEYS = {
      "academic_year.created" => "academic_year_created",
      "academic_year.updated" => "academic_year_updated",
      "academic_year.content_copied" => "academic_year_content_copied",
      "academic_year.students_rolled_over" => "academic_year_students_rolled_over",
      "announcement.created" => "announcement_created",
      "announcement.updated" => "announcement_updated",
      "announcement.deleted" => "announcement_deleted",
      "student.status_updated" => "student_status_updated",
      "student.enrollment_updated" => "student_enrollment_updated",
      "student.password_reset" => "student_password_reset",
      "student.parent_phone_updated" => "student_parent_phone_updated",
      "student.device_removed" => "student_device_removed",
      "support_request.approved" => "support_request_approved",
      "support_request.rejected" => "support_request_rejected",
      "api.sessions.create" => "session_started",
      "api.sessions.destroy" => "session_ended"
    }.freeze

    SECTION_LABELS = {
      "academic_year" => "academic_years", "announcement" => "announcements",
      "student" => "students", "support_request" => "support_requests",
      "api.students" => "students", "api.curriculum" => "content",
      "api.branches" => "content", "api.chapters" => "content",
      "api.lessons" => "content", "api.lectures" => "content",
      "api.video_uploads" => "videos", "api.video_assets" => "videos",
      "api.exams" => "exams", "api.exam_attempts" => "exams",
      "api.activation_codes" => "activation_codes",
      "api.activation_code_batches" => "activation_codes",
      "api.lesson_access_grants" => "lesson_access",
      "api.announcements" => "announcements", "api.support_requests" => "support_requests",
      "api.academic_years" => "academic_years", "api.sessions" => "account"
    }.freeze

    GENERIC_ACTIONS = {
      "create" => "item_created", "update" => "item_updated",
      "destroy" => "item_removed", "complete" => "operation_completed",
      "retry_processing" => "video_processing_retried", "review" => "request_reviewed"
    }.freeze

    def action_description_key(action)
      ACTION_DESCRIPTION_KEYS[action] || GENERIC_ACTIONS.fetch(action.split(".").last, "administrative_action")
    end

    def action_section_key(action)
      key = action.split(".")[0..-2].join(".")
      SECTION_LABELS[key] || SECTION_LABELS[action.split(".").first] || "platform_management"
    end
  end
end
