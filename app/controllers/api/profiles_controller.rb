module Api
  class ProfilesController < ApplicationController
    before_action :authenticate_user!

    def show
      render json: profile_payload
    end

    def update
      current_user.update!(name: profile_params[:name]) if profile_params[:name].present?
      update_student_profile if current_user.student?

      render json: profile_payload
    end

    def password
      return render_invalid_password unless current_user.authenticate(password_params[:current_password])

      current_user.update!(
        password: password_params[:password],
        password_confirmation: password_params[:password_confirmation]
      )
      current_user.user_sessions.active.where.not(id: current_session.id)
        .update_all(status: UserSession.statuses[:ended], ended_at: Time.current, updated_at: Time.current)

      head :no_content
    end

    private

    def profile_params
      params.require(:profile).permit(:name, :governorate)
    end

    def password_params
      params.require(:profile).permit(:current_password, :password, :password_confirmation)
    end

    def update_student_profile
      current_user.student_profile.update!(governorate: profile_params[:governorate]) if profile_params.key?(:governorate)
    end

    def profile_payload
      {
        user: serialize_user(current_user),
        profile: role_profile,
        linked_students: linked_students
      }
    end

    def role_profile
      case current_user.role
      when "student"
        profile = current_user.student_profile
        {
          birth_date: profile.birth_date,
          parent_phone: profile.parent_phone_e164,
          governorate: profile.governorate
        }
      when "parent"
        { verified_phone: current_user.parent_profile.verified_parent_phone_e164 }
      when "assistant"
        { title: current_user.assistant_profile&.title }
      else
        {}
      end
    end

    def linked_students
      return [] unless current_user.parent?

      current_user.parent_profile.student_parent_links.active.includes(student_profile: :user).map do |link|
        student = link.student_profile
        {
          id: student.id,
          name: student.user.name,
          phone: student.user.phone_e164,
          birth_date: student.birth_date,
          governorate: student.governorate,
          status: student.user.status
        }
      end
    end

    def render_invalid_password
      render json: {
        error: { code: "invalid_password", message: "Current password is incorrect" }
      }, status: :unprocessable_entity
    end
  end
end
