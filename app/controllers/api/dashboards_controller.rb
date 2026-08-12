module Api
  class DashboardsController < ApplicationController
    before_action :authenticate_user!

    def show
      payload = if current_user.student?
        student_dashboard
      elsif current_user.teacher?
        management_dashboard
      elsif current_user.assistant?
        management_dashboard
      else
        return render_forbidden
      end

      render json: { dashboard: payload }
    end

    private

    def student_dashboard
      profile = current_user.student_profile
      enrollment = profile.student_enrollments.active.includes(:academic_year, :grade).order(enrolled_at: :desc).first
      return empty_student_dashboard unless enrollment

      lecture_scope = Lecture.joins(lesson: { chapter: :branch })
        .where(status: Lecture.statuses[:published])
        .where("lectures.publish_at IS NULL OR lectures.publish_at <= ?", Time.current)
        .where(branches: { academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id })
      completed = profile.lecture_watch_events.where(lecture_id: lecture_scope.select(:id))
        .where.not(completed_at: nil).distinct.count(:lecture_id)
      completed_ids = profile.lecture_watch_events.where(lecture_id: lecture_scope.select(:id))
        .where.not(completed_at: nil).distinct.pluck(:lecture_id)
      continue_event = profile.lecture_watch_events.where(lecture_id: lecture_scope.select(:id), completed_at: nil)
        .where("last_position_seconds > 0").includes(lecture: { lesson: { chapter: :branch } })
        .order(updated_at: :desc).first
      exams = Exam.published.where(academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id)
      attempt_counts = profile.exam_attempts.where(exam_id: exams.select(:id)).group(:exam_id).count
      approved_extras = profile.support_requests.approved.extra_exam_attempt.pluck(:payload).each_with_object(Hash.new(0)) do |payload, counts|
        exam_id = payload.to_h["exam_id"].to_i
        counts[exam_id] += 1 if exam_id.positive?
      end
      attempts_remaining = exams.sum do |exam|
        [ exam.max_attempts + approved_extras[exam.id] - attempt_counts.fetch(exam.id, 0), 0 ].max
      end

      {
        role: "student",
        enrollment: {
          academic_year: enrollment.academic_year.name,
          grade: enrollment.grade.name,
          grade_level: enrollment.grade.level
        },
        statistics: {
          total_lectures: lecture_scope.count,
          completed_lectures: completed,
          highest_score: profile.exam_attempts.submitted.maximum(:percent)&.to_f,
          subjects_count: Branch.where(academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id).visible.count,
          attempts_remaining: attempts_remaining,
          active_access_grants: profile.lesson_access_grants.currently_active.where(academic_year: enrollment.academic_year).count
        },
        subjects: Branch.where(academic_year_id: enrollment.academic_year_id, grade_id: enrollment.grade_id)
          .visible.includes(chapters: { lessons: :lectures }).ordered.map do |branch|
            lecture_ids = branch.chapters.flat_map(&:lessons).flat_map(&:lectures).select(&:published?).map(&:id)
            {
              id: branch.id, title: branch.title, total_lectures: lecture_ids.length,
              completed_lectures: (lecture_ids & completed_ids).length
            }
          end,
        continue_watching: continue_watching_payload(continue_event),
        announcements: visible_announcements(enrollment.grade_id, current_user.id)
      }
    end

    def empty_student_dashboard
      {
        role: "student", enrollment: nil,
        statistics: {
          total_lectures: 0, completed_lectures: 0, highest_score: nil,
          subjects_count: 0, attempts_remaining: 0, active_access_grants: 0
        },
        subjects: [], continue_watching: nil, announcements: []
      }
    end

    def continue_watching_payload(event)
      return unless event

      lecture = event.lecture
      duration = lecture.duration_seconds.to_i.nonzero? || lecture.video_assets.ready.order(created_at: :desc).pick(:duration_seconds).to_i
      {
        lecture_id: lecture.id,
        title: lecture.title,
        lesson_title: lecture.lesson.title,
        chapter_title: lecture.lesson.chapter.title,
        subject_title: lecture.lesson.chapter.branch.title,
        last_position_seconds: event.last_position_seconds,
        duration_seconds: duration,
        progress_percent: duration.positive? ? [ (event.last_position_seconds.to_f / duration * 100).round, 100 ].min : 0,
        has_thumbnail: lecture.thumbnail_key.present?
      }
    end

    def management_dashboard
      active_students = User.student.active
      last_seen = UserSession.where(user_id: active_students.select(:id)).group(:user_id).maximum(:last_seen_at)
      inactive_count = active_students.count { |student| last_seen[student.id].nil? || last_seen[student.id] < 30.days.ago }
      submitted = ExamAttempt.submitted.includes(student_profile: :user)
      top_scores = submitted.group(:student_profile_id).maximum(:percent)
      top_students = StudentProfile.includes(:user).where(id: top_scores.keys)
        .sort_by { |profile| -top_scores.fetch(profile.id).to_f }.first(5).map do |profile|
          { id: profile.user_id, name: profile.user.name, highest_score: top_scores.fetch(profile.id).to_f }
        end
      watched = LectureWatchEvent.group(:lecture_id).count.sort_by { |_id, count| -count }.first(5)
      lecture_titles = Lecture.where(id: watched.map(&:first)).pluck(:id, :title).to_h

      {
        role: current_user.role,
        statistics: {
          total_students: User.student.count,
          active_students: active_students.count,
          inactive_students: inactive_count,
          risk_students: submitted.where(result_status: %i[risk failed]).distinct.count(:student_profile_id),
          pending_support_requests: SupportRequest.pending.count,
          ready_videos: VideoAsset.ready.count,
          processing_videos: VideoAsset.where(processing_status: %i[uploaded processing]).count,
          failed_videos: VideoAsset.failed.count,
          queued_jobs: SolidQueue::Job.where(finished_at: nil).count,
          failed_jobs: SolidQueue::FailedExecution.count,
          queue_workers: SolidQueue::Process.where("last_heartbeat_at >= ?", 2.minutes.ago).count,
          draft_content: Branch.draft.count + Chapter.draft.count + Lesson.draft.count + Lecture.draft.count
        },
        top_students:,
        recent_content: Lecture.order(updated_at: :desc).limit(5).map do |lecture|
          { id: lecture.id, title: lecture.title, status: lecture.status, updated_at: lecture.updated_at }
        end,
        most_watched: watched.map do |lecture_id, count|
          { id: lecture_id, title: lecture_titles[lecture_id], views: count }
        end
      }
    end

    def visible_announcements(grade_id, user_id)
      targeted = AnnouncementTarget.where(target_type: :user, user_id:).select(:announcement_id)
      grade_targeted = AnnouncementTarget.where(target_type: :grade, grade_id:).select(:announcement_id)
      global = Announcement.left_joins(:announcement_targets).where(announcement_targets: { id: nil }).select(:id)
      Announcement.visible.where(id: targeted).or(Announcement.visible.where(id: grade_targeted))
        .or(Announcement.visible.where(id: global)).order(publish_at: :desc, created_at: :desc).limit(5)
        .map { |record| { id: record.id, title: record.title, body: record.body, publish_at: record.publish_at } }
    end
  end
end
