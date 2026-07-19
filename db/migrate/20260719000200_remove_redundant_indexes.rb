class RemoveRedundantIndexes < ActiveRecord::Migration[8.1]
  REDUNDANT_INDEXES = {
    activation_code_batches: {
      index_activation_code_batches_on_lesson_id: :lesson_id
    },
    activation_codes: {
      index_activation_codes_on_activation_code_batch_id: :activation_code_batch_id,
      index_activation_codes_on_redeemed_by_student_profile_id: :redeemed_by_student_profile_id
    },
    assistant_permissions: {
      index_assistant_permissions_on_assistant_profile_id: :assistant_profile_id
    },
    audit_logs: {
      index_audit_logs_on_actor_user_id: :actor_user_id
    },
    branches: {
      index_branches_on_academic_year_id: :academic_year_id
    },
    chapters: {
      index_chapters_on_branch_id: :branch_id
    },
    device_registrations: {
      index_device_registrations_on_student_profile_id: :student_profile_id
    },
    exam_answers: {
      index_exam_answers_on_exam_attempt_id: :exam_attempt_id
    },
    exam_attempts: {
      index_exam_attempts_on_exam_id: :exam_id,
      index_exam_attempts_on_student_profile_id: :student_profile_id
    },
    exam_choices: {
      index_exam_choices_on_exam_question_id: :exam_question_id
    },
    exam_questions: {
      index_exam_questions_on_exam_id: :exam_id
    },
    exams: {
      index_exams_on_academic_year_id: :academic_year_id,
      index_exams_on_branch_id: :branch_id,
      index_exams_on_chapter_id: :chapter_id,
      index_exams_on_lesson_id: :lesson_id
    },
    lecture_watch_events: {
      index_lecture_watch_events_on_lecture_id: :lecture_id,
      index_lecture_watch_events_on_student_profile_id: :student_profile_id
    },
    lectures: {
      index_lectures_on_lesson_id: :lesson_id
    },
    lesson_access_grants: {
      index_lesson_access_grants_on_lesson_id: :lesson_id,
      index_lesson_access_grants_on_student_profile_id: :student_profile_id
    },
    lessons: {
      index_lessons_on_chapter_id: :chapter_id
    },
    parent_phone_changes: {
      index_parent_phone_changes_on_student_profile_id: :student_profile_id
    },
    student_enrollments: {
      index_student_enrollments_on_academic_year_id: :academic_year_id,
      index_student_enrollments_on_student_profile_id: :student_profile_id
    },
    student_parent_links: {
      index_student_parent_links_on_parent_profile_id: :parent_profile_id,
      index_student_parent_links_on_student_profile_id: :student_profile_id
    },
    support_request_actions: {
      index_support_request_actions_on_support_request_id: :support_request_id
    },
    support_requests: {
      index_support_requests_on_requester_user_id: :requester_user_id,
      index_support_requests_on_student_profile_id: :student_profile_id
    },
    user_sessions: {
      index_user_sessions_on_user_id: :user_id
    },
    video_assets: {
      index_video_assets_on_lecture_id: :lecture_id
    },
    video_variants: {
      index_video_variants_on_video_asset_id: :video_asset_id
    }
  }.freeze

  def up
    each_index do |table, name, _column|
      remove_index table, name: name if index_name_exists?(table, name)
    end
  end

  def down
    each_index do |table, name, column|
      add_index table, column, name: name unless index_name_exists?(table, name)
    end
  end

  private

  def each_index
    REDUNDANT_INDEXES.each do |table, indexes|
      indexes.each { |name, column| yield table, name, column }
    end
  end
end
