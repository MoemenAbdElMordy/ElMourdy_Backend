module Videos
  class Access
    def self.allowed?(user:, lecture:)
      return true if user.teacher?
      return assistant_allowed?(user) if user.assistant?
      return false unless user.student?
      enrollment = user.student_profile.student_enrollments.active.includes(:grade).order(enrolled_at: :desc).first
      return false unless enrollment

      eligible_lessons = lecture.all_lessons.joins(chapter: :branch).where(
        branches: { academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id }
      )
      return false unless eligible_lessons.exists?
      return true if lecture.is_free? || eligible_lessons.where(is_free: true).exists?

      user.student_profile.lesson_access_grants.currently_active.exists?(
        lesson_id: eligible_lessons.select(:id),
        academic_year_id: enrollment.academic_year_id
      )
    end

    def self.assistant_allowed?(user)
      user.assistant_profile&.assistant_permissions&.where(enabled: true)&.exists?(
        permission_key: %w[manage_content upload_videos]
      ) || false
    end
    private_class_method :assistant_allowed?
  end
end
