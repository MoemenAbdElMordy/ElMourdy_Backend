module Api
  class AnnouncementsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_management!, except: :index

    def index
      announcements = if current_user.student?
        enrollment = current_user.student_profile.student_enrollments.active.order(enrolled_at: :desc).first
        next_visible_announcements(enrollment&.grade_id, current_user.id)
      elsif current_user.parent?
        grade_ids = current_user.parent_profile.student_profiles.joins(:student_enrollments)
          .merge(StudentEnrollment.active).distinct.pluck("student_enrollments.grade_id")
        next_visible_announcements(grade_ids, current_user.id)
      else
        require_teacher_or_assistant_permission!("manage_announcements")
        return if performed?

        Announcement.all
      end
      announcements = announcements.includes(:announcement_targets).order(publish_at: :desc, created_at: :desc)
      announcements, pagination = paginate(announcements)
      render json: { announcements: announcements.map { |record| serialize(record) }, pagination: }
    end

    def create
      announcement = Announcement.transaction do
        record = Announcement.create!(announcement_params.except(:grade_ids, :user_ids).merge(created_by_user: current_user))
        replace_targets(record, announcement_params[:grade_ids], announcement_params[:user_ids])
        record
      end
      audit!(action: "announcement.created", target: announcement)
      render json: { announcement: serialize(announcement) }, status: :created
    end

    def update
      announcement = Announcement.find(params[:id])
      Announcement.transaction do
        announcement.update!(announcement_params.except(:grade_ids, :user_ids))
        if announcement_params.key?(:grade_ids) || announcement_params.key?(:user_ids)
          replace_targets(announcement, announcement_params[:grade_ids], announcement_params[:user_ids])
        end
      end
      audit!(action: "announcement.updated", target: announcement)
      render json: { announcement: serialize(announcement.reload) }
    end

    def destroy
      announcement = Announcement.find(params[:id])
      audit!(action: "announcement.deleted", target: announcement)
      announcement.destroy!
      head :no_content
    end

    private

    def authorize_management!
      require_teacher_or_assistant_permission!("manage_announcements")
    end

    def next_visible_announcements(grade_ids, user_id)
      target_ids = AnnouncementTarget.where(target_type: :user, user_id:).select(:announcement_id)
      grade_target_ids = AnnouncementTarget.where(target_type: :grade, grade_id: grade_ids).select(:announcement_id)
      untargeted_ids = Announcement.left_joins(:announcement_targets).where(announcement_targets: { id: nil }).select(:id)
      Announcement.visible.where(id: target_ids).or(Announcement.visible.where(id: grade_target_ids)).or(Announcement.visible.where(id: untargeted_ids))
    end

    def announcement_params
      params.require(:announcement).permit(:title, :body, :status, :publish_at, grade_ids: [], user_ids: [])
    end

    def replace_targets(announcement, grade_ids, user_ids)
      announcement.announcement_targets.destroy_all
      Array(grade_ids).reject(&:blank?).uniq.each do |grade_id|
        announcement.announcement_targets.create!(target_type: :grade, grade_id:)
      end
      Array(user_ids).reject(&:blank?).uniq.each do |user_id|
        user = User.student.find(user_id)
        announcement.announcement_targets.create!(target_type: :user, user:)
      end
    end

    def serialize(record)
      {
        id: record.id, title: record.title, body: record.body, status: record.status,
        publish_at: record.publish_at, created_at: record.created_at,
        grade_ids: record.announcement_targets.select(&:target_grade?).map(&:grade_id),
        user_ids: record.announcement_targets.select(&:target_user?).map(&:user_id)
      }
    end
  end
end
