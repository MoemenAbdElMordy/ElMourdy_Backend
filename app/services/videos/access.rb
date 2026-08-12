module Videos
  class Access
    def self.allowed?(user:, lecture:)
      return true if user.teacher?
      return assistant_allowed?(user) if user.assistant?
      return false unless user.student?
      return true if lecture.is_free? || lecture.lesson.is_free?

      enrollment = user.student_profile.student_enrollments.active
        .find_by(academic_year_id: lecture.lesson.chapter.branch.academic_year_id)
      return false unless enrollment

      user.student_profile.lesson_access_grants.currently_active.exists?(
        lesson_id: lecture.lesson_id,
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
