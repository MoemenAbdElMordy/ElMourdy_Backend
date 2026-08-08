module Api
  class ActivationCodesController < ApplicationController
    before_action :authenticate_user!

    def redeem
      return render_forbidden unless current_user.student?

      grant = ActivationCodes::Redeem.call(raw_code: params.require(:code), student_profile: current_user.student_profile)
      render json: { access_grant: serialize_grant(grant) }, status: :created
    end

    def update
      require_teacher_or_assistant_permission!("manage_codes")
      return if performed?

      code = ActivationCode.find(params[:id])
      raise ApplicationService::Error, "Only unused activation codes can be disabled" unless code.unused?

      code.update!(status: :disabled)
      render json: { activation_code: { id: code.id, status: code.status } }
    end

    def destroy
      require_teacher_or_assistant_permission!("manage_codes")
      return if performed?

      code = ActivationCode.find(params[:id])
      raise ApplicationService::Error, "Only unused activation codes can be deleted" unless code.unused?

      code.update!(status: :deleted, deleted_at: Time.current)
      head :no_content
    end

    private

    def serialize_grant(grant)
      { id: grant.id, lesson_id: grant.lesson_id, lesson: grant.lesson.title, source: grant.source, expires_on: grant.expires_on, status: grant.status }
    end
  end
end
