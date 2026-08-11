module Api
  class ParentsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_teacher!

    def index
      users = User.parent.includes(parent_profile: { student_parent_links: { student_profile: :user } })
      users = users.where(status: params[:status]) if User.statuses.key?(params[:status])
      if params[:query].present?
        users = users.where("users.name LIKE :query OR users.phone_e164 LIKE :query", query: "%#{params[:query]}%")
      end
      render json: { parents: users.order(created_at: :desc).map { |user| serialize_parent(user) } }
    end

    def show
      render json: { parent: serialize_parent(parent_user, detailed: true) }
    end

    def update
      user = parent_user
      user.update!(parent_params)
      revoke_sessions(user) unless user.active?
      audit!(action: "parent.updated", target: user, metadata: { status: user.status })
      render json: { parent: serialize_parent(user, detailed: true) }
    end

    def password
      user = parent_user
      password = password_params.fetch(:password)
      user.update!(password:, password_confirmation: password)
      revoke_sessions(user)
      audit!(action: "parent.password_reset", target: user)
      head :no_content
    end

    private

    def parent_user
      User.parent.includes(parent_profile: { student_parent_links: { student_profile: :user } }).find(params[:id])
    end

    def parent_params
      params.require(:parent).permit(:name, :email, :status)
    end

    def password_params
      params.require(:parent).permit(:password)
    end

    def revoke_sessions(user)
      user.user_sessions.active.update_all(status: UserSession.statuses[:revoked], ended_at: Time.current)
    end

    def serialize_parent(user, detailed: false)
      profile = user.parent_profile
      links = profile.student_parent_links.active.includes(student_profile: :user)
      payload = {
        id: user.id, name: user.name, phone: user.phone_e164, email: user.email,
        status: user.status, verified_phone: profile.verified_parent_phone_e164,
        students_count: links.size, created_at: user.created_at,
        last_active_at: user.user_sessions.maximum(:last_seen_at)
      }
      return payload unless detailed

      payload.merge(students: links.map do |link|
        student = link.student_profile
        { id: student.user_id, name: student.user.name, phone: student.user.phone_e164, relation: link.relation }
      end)
    end
  end
end
