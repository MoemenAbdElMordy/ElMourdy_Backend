module Api
  class ActivationCodesController < ApplicationController
    before_action :authenticate_user!

    def redeem
      return render_forbidden unless current_user.student?

      lecture = Lecture.find(params[:lecture_id]) if params[:lecture_id].present?
      grant = ActivationCodes::Redeem.call(
        raw_code: params.require(:code),
        student_profile: current_user.student_profile,
        lecture:
      )
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
      if grant.is_a?(LectureAccessGrant)
        return {
          id: grant.id, lecture_id: grant.lecture_id, lecture: grant.lecture.title,
          expires_on: grant.expires_on, status: grant.status, access_type: "lecture"
        }
      end

      {
        id: grant.id, lesson_id: grant.lesson_id, lesson: grant.lesson.title, source: grant.source,
        expires_on: grant.expires_on, status: grant.status, access_type: "lesson"
      }
    end
  end
end
