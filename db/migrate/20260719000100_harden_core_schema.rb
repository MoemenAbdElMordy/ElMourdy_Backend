class HardenCoreSchema < ActiveRecord::Migration[8.1]
  def up
    add_domain_check_constraints
    apply_owned_child_delete_policies
    apply_historical_actor_delete_policies
  end

  def down
    restore_default_delete_policies
    remove_all_owned_check_constraints
  end

  private

  def add_domain_check_constraints
    add_enum_check_constraints
    add_check_constraint :academic_years, "starts_on < ends_on", name: "chk_academic_year_dates"
    add_check_constraint :grades, "level BETWEEN 1 AND 3", name: "chk_grade_level"

    add_positive_position_constraint :branches
    add_positive_position_constraint :chapters
    add_positive_position_constraint :lessons
    add_positive_position_constraint :lectures
    add_positive_position_constraint :exam_questions
    add_positive_position_constraint :exam_choices

    add_check_constraint :lessons,
      "pass_required_percent IS NULL OR pass_required_percent BETWEEN 0 AND 100",
      name: "chk_lesson_pass_percent"
    add_check_constraint :lessons,
      "(requires_exam_pass = FALSE AND required_exam_id IS NULL) OR " \
      "(requires_exam_pass = TRUE AND required_exam_id IS NOT NULL AND pass_required_percent IS NOT NULL)",
      name: "chk_lesson_exam_requirement"

    add_check_constraint :lectures,
      "duration_seconds IS NULL OR duration_seconds > 0",
      name: "chk_lecture_duration"
    add_check_constraint :video_assets,
      "duration_seconds IS NULL OR duration_seconds > 0",
      name: "chk_video_asset_duration"
    add_check_constraint :video_variants,
      "size_bytes IS NULL OR size_bytes > 0",
      name: "chk_video_variant_size"

    add_check_constraint :exams, "duration_minutes > 0", name: "chk_exam_duration"
    add_check_constraint :exams, "max_attempts > 0", name: "chk_exam_max_attempts"
    add_check_constraint :exams,
      "pass_percent BETWEEN 0 AND 100 AND " \
      "risk_from_percent BETWEEN 0 AND 100 AND " \
      "risk_to_percent BETWEEN 0 AND 100 AND " \
      "risk_from_percent <= risk_to_percent",
      name: "chk_exam_percentages"
    add_check_constraint :exams,
      "(scope_type = 0 AND lesson_id IS NOT NULL AND chapter_id IS NULL AND branch_id IS NULL) OR " \
      "(scope_type = 1 AND lesson_id IS NULL AND chapter_id IS NOT NULL AND branch_id IS NULL) OR " \
      "(scope_type = 2 AND lesson_id IS NULL AND chapter_id IS NULL AND branch_id IS NOT NULL) OR " \
      "(scope_type = 3 AND lesson_id IS NULL AND chapter_id IS NULL AND branch_id IS NULL)",
      name: "chk_exam_scope"
    add_check_constraint :exam_questions, "points > 0", name: "chk_exam_question_points"

    add_check_constraint :activation_code_batches, "quantity > 0", name: "chk_code_batch_quantity"
    add_check_constraint :activation_codes,
      "(status = 1 AND redeemed_by_student_profile_id IS NOT NULL AND redeemed_at IS NOT NULL) OR " \
      "(status <> 1 AND redeemed_by_student_profile_id IS NULL AND redeemed_at IS NULL)",
      name: "chk_activation_code_redemption"

    add_check_constraint :exam_attempts, "attempt_number > 0", name: "chk_attempt_number"
    add_check_constraint :exam_attempts,
      "percent IS NULL OR percent BETWEEN 0 AND 100",
      name: "chk_attempt_percent"
    add_check_constraint :exam_attempts,
      "score_points IS NULL OR score_points >= 0",
      name: "chk_attempt_score"
    add_check_constraint :exam_attempts,
      "max_points IS NULL OR max_points > 0",
      name: "chk_attempt_max_points"
    add_check_constraint :exam_answers,
      "points_awarded IS NULL OR points_awarded >= 0",
      name: "chk_answer_points"

    add_check_constraint :lecture_watch_events,
      "last_position_seconds >= 0",
      name: "chk_watch_position"
    add_check_constraint :otp_verifications,
      "attempts_count >= 0",
      name: "chk_otp_attempts"
    add_check_constraint :otp_verifications,
      "expires_at > created_at",
      name: "chk_otp_expiration"
    add_check_constraint :parent_phone_changes,
      "old_phone_e164 <> new_phone_e164",
      name: "chk_parent_phone_changed"
    add_check_constraint :announcement_targets,
      "(target_type = 0 AND grade_id IS NOT NULL AND user_id IS NULL) OR " \
      "(target_type = 1 AND grade_id IS NULL AND user_id IS NOT NULL)",
      name: "chk_announcement_target"
  end

  def add_enum_check_constraints
    add_enum_constraint :users, :role, 0..3
    add_enum_constraint :users, :status, 0..2
    add_enum_constraint :student_parent_links, :relation, 0..3
    add_enum_constraint :student_parent_links, :status, 0..1
    add_enum_constraint :academic_years, :status, 0..2
    add_enum_constraint :student_enrollments, :status, 0..2
    %i[branches chapters lessons lectures].each { |table| add_enum_constraint table, :status, 0..3 }
    add_enum_constraint :video_assets, :processing_status, 0..3
    add_enum_constraint :video_variants, :status, 0..2
    add_enum_constraint :exams, :scope_type, 0..3
    add_enum_constraint :exams, :attempt_form_mode, 0..1
    add_enum_constraint :exams, :status, 0..3
    add_enum_constraint :activation_codes, :status, 0..3
    add_enum_constraint :lesson_access_grants, :source, 0..2
    add_enum_constraint :lesson_access_grants, :status, 0..2
    add_enum_constraint :exam_attempts, :result_status, 0..2, nullable: true
    add_enum_constraint :exam_attempts, :status, 0..2
    add_enum_constraint :device_registrations, :status, 0..2
    add_enum_constraint :user_sessions, :status, 0..2
    add_enum_constraint :otp_verifications, :purpose, 0..2
    add_enum_constraint :otp_verifications, :status, 0..3
    add_enum_constraint :support_requests, :request_type, 0..2
    add_enum_constraint :support_requests, :status, 0..3
    add_enum_constraint :support_request_actions, :action, 0..2
    add_enum_constraint :parent_phone_changes, :status, 0..3
    add_enum_constraint :announcements, :status, 0..2
    add_enum_constraint :announcement_targets, :target_type, 0..1
  end

  def add_enum_constraint(table, column, range, nullable: false)
    expression = "#{column} BETWEEN #{range.begin} AND #{range.end}"
    expression = "#{column} IS NULL OR #{expression}" if nullable
    add_check_constraint table, expression, name: "chk_#{table}_#{column}"
  end

  def add_positive_position_constraint(table)
    add_check_constraint table, "position > 0", name: "chk_#{table}_position"
  end

  def apply_owned_child_delete_policies
    replace_foreign_key :assistant_permissions, :assistant_profiles, on_delete: :cascade
    replace_foreign_key :video_variants, :video_assets, on_delete: :cascade
    replace_foreign_key :support_request_actions, :support_requests, on_delete: :cascade
    replace_foreign_key :announcement_targets, :announcements, on_delete: :cascade
  end

  def apply_historical_actor_delete_policies
    replace_foreign_key :video_assets, :users, column: :created_by_user_id, on_delete: :nullify
    replace_foreign_key :exams, :users, column: :created_by_user_id, on_delete: :nullify
    replace_foreign_key :activation_code_batches, :users, column: :created_by_user_id, on_delete: :nullify
    replace_foreign_key :announcements, :users, column: :created_by_user_id, on_delete: :nullify
    replace_foreign_key :audit_logs, :users, column: :actor_user_id, on_delete: :nullify
    replace_foreign_key :otp_verifications, :users, on_delete: :nullify
  end

  def replace_foreign_key(from_table, to_table, column: nil, on_delete:)
    options = column ? { column: column } : {}
    remove_foreign_key from_table, to_table, **options
    options[:on_delete] = on_delete if on_delete
    add_foreign_key from_table, to_table, **options
  end

  def restore_default_delete_policies
    replace_foreign_key :assistant_permissions, :assistant_profiles, on_delete: nil
    replace_foreign_key :video_variants, :video_assets, on_delete: nil
    replace_foreign_key :support_request_actions, :support_requests, on_delete: nil
    replace_foreign_key :announcement_targets, :announcements, on_delete: nil
    replace_foreign_key :video_assets, :users, column: :created_by_user_id, on_delete: nil
    replace_foreign_key :exams, :users, column: :created_by_user_id, on_delete: nil
    replace_foreign_key :activation_code_batches, :users, column: :created_by_user_id, on_delete: nil
    replace_foreign_key :announcements, :users, column: :created_by_user_id, on_delete: nil
    replace_foreign_key :audit_logs, :users, column: :actor_user_id, on_delete: nil
    replace_foreign_key :otp_verifications, :users, on_delete: nil
  end

  def remove_all_owned_check_constraints
    connection.tables.each do |table|
      connection.check_constraints(table).each do |constraint|
        remove_check_constraint table, name: constraint.name if constraint.name.start_with?("chk_")
      end
    end
  end
end
