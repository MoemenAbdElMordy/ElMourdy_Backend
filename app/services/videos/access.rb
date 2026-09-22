module Videos
  class Access
    def self.allowed?(user:, lecture:)
      return true if user.teacher?
      return assistant_allowed?(user) if user.assistant?
      return false unless user.student?
      return false unless Lecture.visible.exists?(id: lecture.id)
      enrollment = user.student_profile.student_enrollments.active.includes(:grade).order(enrolled_at: :desc).first
      return false unless enrollment

      eligible_lessons = lecture.all_lessons.joins(chapter: :branch).where(
        branches: { academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id }
      )
      return false unless eligible_lessons.exists?
      branch_ids = eligible_lessons.distinct.pluck("branches.id")
      presentation_visible = Curriculum::PresentationVisibility.visible?(lecture:, branch_ids:)
      if presentation_visible.nil?
        return false unless eligible_lessons.merge(Lesson.visible).merge(Chapter.visible).merge(Branch.visible).exists?
      else
        return false unless presentation_visible
      end
      return true if lecture.is_free? || eligible_lessons.where(is_free: true).exists?
      return true if user.student_profile.lecture_access_grants.currently_active.exists?(
        lecture_id: lecture.id,
        academic_year_id: enrollment.academic_year_id
      )

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
