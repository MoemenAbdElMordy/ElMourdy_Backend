# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_19_000200) do
  create_table "academic_years", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "copied_from_year_id"
    t.datetime "created_at", null: false
    t.date "ends_on", null: false
    t.string "name", null: false
    t.date "starts_on", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["copied_from_year_id"], name: "index_academic_years_on_copied_from_year_id"
    t.index ["name"], name: "index_academic_years_on_name", unique: true
    t.index ["status", "starts_on"], name: "index_academic_years_on_status_and_starts_on"
    t.check_constraint "`starts_on` < `ends_on`", name: "chk_academic_year_dates"
    t.check_constraint "`status` between 0 and 2", name: "chk_academic_years_status"
  end

  create_table "activation_code_batches", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "academic_year_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.datetime "deleted_at"
    t.date "expires_on", null: false
    t.bigint "grade_id", null: false
    t.bigint "lesson_id", null: false
    t.string "name", null: false
    t.integer "quantity", null: false
    t.datetime "updated_at", null: false
    t.index ["academic_year_id"], name: "index_activation_code_batches_on_academic_year_id"
    t.index ["created_by_user_id"], name: "index_activation_code_batches_on_created_by_user_id"
    t.index ["grade_id"], name: "index_activation_code_batches_on_grade_id"
    t.index ["lesson_id", "academic_year_id", "grade_id", "deleted_at"], name: "idx_code_batches_scope"
    t.check_constraint "`quantity` > 0", name: "chk_code_batch_quantity"
  end

  create_table "activation_codes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "activation_code_batch_id", null: false
    t.text "code_ciphertext"
    t.string "code_digest", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "redeemed_at"
    t.bigint "redeemed_by_student_profile_id"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["activation_code_batch_id", "status", "id"], name: "idx_codes_batch_status"
    t.index ["code_digest"], name: "index_activation_codes_on_code_digest", unique: true
    t.index ["redeemed_by_student_profile_id", "redeemed_at"], name: "idx_student_redemptions"
    t.check_constraint "((`status` = 1) and (`redeemed_by_student_profile_id` is not null) and (`redeemed_at` is not null)) or ((`status` <> 1) and (`redeemed_by_student_profile_id` is null) and (`redeemed_at` is null))", name: "chk_activation_code_redemption"
    t.check_constraint "`status` between 0 and 3", name: "chk_activation_codes_status"
  end

  create_table "announcement_targets", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "announcement_id", null: false
    t.datetime "created_at", null: false
    t.bigint "grade_id"
    t.integer "target_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["announcement_id"], name: "index_announcement_targets_on_announcement_id"
    t.index ["grade_id"], name: "index_announcement_targets_on_grade_id"
    t.index ["target_type", "grade_id", "announcement_id"], name: "idx_grade_announcement_targets"
    t.index ["target_type", "user_id", "announcement_id"], name: "idx_user_announcement_targets"
    t.index ["user_id"], name: "index_announcement_targets_on_user_id"
    t.check_constraint "((`target_type` = 0) and (`grade_id` is not null) and (`user_id` is null)) or ((`target_type` = 1) and (`grade_id` is null) and (`user_id` is not null))", name: "chk_announcement_target"
    t.check_constraint "`target_type` between 0 and 1", name: "chk_announcement_targets_target_type"
  end

  create_table "announcements", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.datetime "publish_at"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_announcements_on_created_by_user_id"
    t.index ["status", "publish_at"], name: "index_announcements_on_status_and_publish_at"
    t.check_constraint "`status` between 0 and 2", name: "chk_announcements_status"
  end

  create_table "assistant_permissions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "assistant_profile_id", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "permission_key", null: false
    t.datetime "updated_at", null: false
    t.index ["assistant_profile_id", "permission_key"], name: "idx_assistant_permissions_unique", unique: true
  end

  create_table "assistant_profiles", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.boolean "can_login", default: true, null: false
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_assistant_profiles_on_user_id", unique: true
  end

  create_table "audit_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_user_id"
    t.datetime "created_at", null: false
    t.string "ip_address", limit: 45
    t.json "metadata"
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.index ["action", "created_at"], name: "index_audit_logs_on_action_and_created_at"
    t.index ["actor_user_id", "created_at"], name: "index_audit_logs_on_actor_user_id_and_created_at"
    t.index ["target_type", "target_id", "created_at"], name: "idx_audit_target"
  end

  create_table "branches", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "academic_year_id", null: false
    t.datetime "created_at", null: false
    t.bigint "grade_id", null: false
    t.integer "position", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["academic_year_id", "grade_id", "position"], name: "idx_branch_position_unique", unique: true
    t.index ["academic_year_id", "grade_id", "status", "position"], name: "idx_published_branches"
    t.index ["grade_id"], name: "index_branches_on_grade_id"
    t.check_constraint "`position` > 0", name: "chk_branches_position"
    t.check_constraint "`status` between 0 and 3", name: "chk_branches_status"
  end

  create_table "chapters", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "branch_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "position"], name: "index_chapters_on_branch_id_and_position", unique: true
    t.index ["branch_id", "status", "position"], name: "index_chapters_on_branch_id_and_status_and_position"
    t.check_constraint "`position` > 0", name: "chk_chapters_position"
    t.check_constraint "`status` between 0 and 3", name: "chk_chapters_status"
  end

  create_table "device_registrations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "browser"
    t.datetime "created_at", null: false
    t.string "device_fingerprint_digest", limit: 64, null: false
    t.string "device_name"
    t.string "ip_address", limit: 45
    t.datetime "last_seen_at"
    t.datetime "last_self_removed_at"
    t.string "os"
    t.datetime "removed_at"
    t.integer "status", default: 0, null: false
    t.bigint "student_profile_id", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["student_profile_id", "device_fingerprint_digest"], name: "idx_student_device_unique", unique: true
    t.index ["student_profile_id", "status", "last_seen_at"], name: "idx_active_devices"
    t.check_constraint "`status` between 0 and 2", name: "chk_device_registrations_status"
  end

  create_table "exam_answers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "exam_attempt_id", null: false
    t.bigint "exam_question_id", null: false
    t.boolean "is_correct"
    t.decimal "points_awarded", precision: 8, scale: 2
    t.bigint "selected_choice_id"
    t.datetime "updated_at", null: false
    t.index ["exam_attempt_id", "exam_question_id"], name: "idx_attempt_answer_unique", unique: true
    t.index ["exam_question_id"], name: "index_exam_answers_on_exam_question_id"
    t.index ["selected_choice_id"], name: "index_exam_answers_on_selected_choice_id"
    t.check_constraint "(`points_awarded` is null) or (`points_awarded` >= 0)", name: "chk_answer_points"
  end

  create_table "exam_attempts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "attempt_number", null: false
    t.datetime "created_at", null: false
    t.bigint "exam_id", null: false
    t.decimal "max_points", precision: 10, scale: 2
    t.decimal "percent", precision: 5, scale: 2
    t.json "question_order"
    t.integer "result_status"
    t.decimal "score_points", precision: 10, scale: 2
    t.datetime "started_at", null: false
    t.integer "status", default: 0, null: false
    t.bigint "student_profile_id", null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["exam_id", "status", "submitted_at"], name: "index_exam_attempts_on_exam_id_and_status_and_submitted_at"
    t.index ["exam_id", "student_profile_id", "attempt_number"], name: "idx_exam_attempt_unique", unique: true
    t.index ["student_profile_id", "submitted_at"], name: "index_exam_attempts_on_student_profile_id_and_submitted_at"
    t.check_constraint "(`max_points` is null) or (`max_points` > 0)", name: "chk_attempt_max_points"
    t.check_constraint "(`percent` is null) or (`percent` between 0 and 100)", name: "chk_attempt_percent"
    t.check_constraint "(`result_status` is null) or (`result_status` between 0 and 2)", name: "chk_exam_attempts_result_status"
    t.check_constraint "(`score_points` is null) or (`score_points` >= 0)", name: "chk_attempt_score"
    t.check_constraint "`attempt_number` > 0", name: "chk_attempt_number"
    t.check_constraint "`status` between 0 and 2", name: "chk_exam_attempts_status"
  end

  create_table "exam_choices", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "exam_question_id", null: false
    t.boolean "is_correct", default: false, null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["exam_question_id", "position"], name: "index_exam_choices_on_exam_question_id_and_position", unique: true
    t.check_constraint "`position` > 0", name: "chk_exam_choices_position"
  end

  create_table "exam_questions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "exam_id", null: false
    t.text "explanation"
    t.decimal "points", precision: 8, scale: 2, default: "1.0", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["exam_id", "position"], name: "index_exam_questions_on_exam_id_and_position", unique: true
    t.check_constraint "`points` > 0", name: "chk_exam_question_points"
    t.check_constraint "`position` > 0", name: "chk_exam_questions_position"
  end

  create_table "exams", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "academic_year_id", null: false
    t.integer "attempt_form_mode", default: 0, null: false
    t.bigint "branch_id"
    t.bigint "chapter_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.integer "duration_minutes", null: false
    t.bigint "grade_id", null: false
    t.bigint "lesson_id"
    t.integer "max_attempts", default: 3, null: false
    t.integer "pass_percent", default: 50, null: false
    t.integer "risk_from_percent", default: 50, null: false
    t.integer "risk_to_percent", default: 60, null: false
    t.integer "scope_type", null: false
    t.boolean "show_result_immediately", default: true, null: false
    t.boolean "shuffle_choices", default: false, null: false
    t.boolean "shuffle_questions", default: false, null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["academic_year_id", "grade_id", "status", "scope_type"], name: "idx_exams_year_grade"
    t.index ["branch_id", "status"], name: "index_exams_on_branch_id_and_status"
    t.index ["chapter_id", "status"], name: "index_exams_on_chapter_id_and_status"
    t.index ["created_by_user_id"], name: "index_exams_on_created_by_user_id"
    t.index ["grade_id"], name: "index_exams_on_grade_id"
    t.index ["lesson_id", "status"], name: "index_exams_on_lesson_id_and_status"
    t.check_constraint "((`scope_type` = 0) and (`lesson_id` is not null) and (`chapter_id` is null) and (`branch_id` is null)) or ((`scope_type` = 1) and (`lesson_id` is null) and (`chapter_id` is not null) and (`branch_id` is null)) or ((`scope_type` = 2) and (`lesson_id` is null) and (`chapter_id` is null) and (`branch_id` is not null)) or ((`scope_type` = 3) and (`lesson_id` is null) and (`chapter_id` is null) and (`branch_id` is null))", name: "chk_exam_scope"
    t.check_constraint "(`pass_percent` between 0 and 100) and (`risk_from_percent` between 0 and 100) and (`risk_to_percent` between 0 and 100) and (`risk_from_percent` <= `risk_to_percent`)", name: "chk_exam_percentages"
    t.check_constraint "`attempt_form_mode` between 0 and 1", name: "chk_exams_attempt_form_mode"
    t.check_constraint "`duration_minutes` > 0", name: "chk_exam_duration"
    t.check_constraint "`max_attempts` > 0", name: "chk_exam_max_attempts"
    t.check_constraint "`scope_type` between 0 and 3", name: "chk_exams_scope_type"
    t.check_constraint "`status` between 0 and 3", name: "chk_exams_status"
  end

  create_table "grades", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "level", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "level"], name: "index_grades_on_active_and_level"
    t.index ["level"], name: "index_grades_on_level", unique: true
    t.check_constraint "`level` between 1 and 3", name: "chk_grade_level"
  end

  create_table "lecture_watch_events", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "device_registration_id"
    t.string "ip_address", limit: 45
    t.integer "last_position_seconds", default: 0, null: false
    t.bigint "lecture_id", null: false
    t.datetime "started_at", null: false
    t.bigint "student_profile_id", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["device_registration_id"], name: "index_lecture_watch_events_on_device_registration_id"
    t.index ["lecture_id", "started_at"], name: "index_lecture_watch_events_on_lecture_id_and_started_at"
    t.index ["student_profile_id", "lecture_id", "started_at"], name: "idx_student_lecture_watch"
    t.check_constraint "`last_position_seconds` >= 0", name: "chk_watch_position"
  end

  create_table "lectures", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.boolean "is_free", default: false, null: false
    t.bigint "lesson_id", null: false
    t.integer "position", null: false
    t.datetime "publish_at"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id", "position"], name: "index_lectures_on_lesson_id_and_position", unique: true
    t.index ["lesson_id", "status", "publish_at", "position"], name: "idx_published_lectures"
    t.check_constraint "(`duration_seconds` is null) or (`duration_seconds` > 0)", name: "chk_lecture_duration"
    t.check_constraint "`position` > 0", name: "chk_lectures_position"
    t.check_constraint "`status` between 0 and 3", name: "chk_lectures_status"
  end

  create_table "lesson_access_grants", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "academic_year_id", null: false
    t.bigint "activation_code_id"
    t.datetime "created_at", null: false
    t.date "expires_on", null: false
    t.bigint "lesson_id", null: false
    t.integer "source", null: false
    t.integer "status", default: 0, null: false
    t.bigint "student_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["academic_year_id"], name: "index_lesson_access_grants_on_academic_year_id"
    t.index ["activation_code_id"], name: "index_lesson_access_grants_on_activation_code_id"
    t.index ["lesson_id", "academic_year_id", "status"], name: "idx_lesson_grant_report"
    t.index ["student_profile_id", "academic_year_id", "status", "expires_on"], name: "idx_student_active_grants"
    t.index ["student_profile_id", "lesson_id", "academic_year_id"], name: "idx_lesson_grant_unique", unique: true
    t.check_constraint "`source` between 0 and 2", name: "chk_lesson_access_grants_source"
    t.check_constraint "`status` between 0 and 2", name: "chk_lesson_access_grants_status"
  end

  create_table "lessons", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "chapter_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_free", default: false, null: false
    t.integer "pass_required_percent"
    t.integer "position", null: false
    t.datetime "publish_at"
    t.bigint "required_exam_id"
    t.boolean "requires_exam_pass", default: false, null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["chapter_id", "position"], name: "index_lessons_on_chapter_id_and_position", unique: true
    t.index ["chapter_id", "status", "publish_at", "position"], name: "idx_published_lessons"
    t.index ["required_exam_id"], name: "index_lessons_on_required_exam_id"
    t.check_constraint "((`requires_exam_pass` = false) and (`required_exam_id` is null)) or ((`requires_exam_pass` = true) and (`required_exam_id` is not null) and (`pass_required_percent` is not null))", name: "chk_lesson_exam_requirement"
    t.check_constraint "(`pass_required_percent` is null) or (`pass_required_percent` between 0 and 100)", name: "chk_lesson_pass_percent"
    t.check_constraint "`position` > 0", name: "chk_lessons_position"
    t.check_constraint "`status` between 0 and 3", name: "chk_lessons_status"
  end

  create_table "otp_verifications", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.string "code_digest", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.json "metadata"
    t.string "phone_e164", limit: 20, null: false
    t.integer "purpose", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.datetime "verified_at"
    t.index ["phone_e164", "purpose", "status", "created_at"], name: "idx_latest_otp"
    t.index ["status", "expires_at"], name: "index_otp_verifications_on_status_and_expires_at"
    t.index ["user_id"], name: "index_otp_verifications_on_user_id"
    t.check_constraint "`attempts_count` >= 0", name: "chk_otp_attempts"
    t.check_constraint "`expires_at` > `created_at`", name: "chk_otp_expiration"
    t.check_constraint "`purpose` between 0 and 2", name: "chk_otp_verifications_purpose"
    t.check_constraint "`status` between 0 and 3", name: "chk_otp_verifications_status"
  end

  create_table "parent_phone_changes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.string "new_phone_e164", limit: 20, null: false
    t.string "old_phone_e164", limit: 20, null: false
    t.bigint "otp_verification_id"
    t.bigint "requested_by_user_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "student_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["otp_verification_id"], name: "index_parent_phone_changes_on_otp_verification_id"
    t.index ["requested_by_user_id"], name: "index_parent_phone_changes_on_requested_by_user_id"
    t.index ["student_profile_id", "status", "created_at"], name: "idx_parent_phone_change_state"
    t.check_constraint "`old_phone_e164` <> `new_phone_e164`", name: "chk_parent_phone_changed"
    t.check_constraint "`status` between 0 and 3", name: "chk_parent_phone_changes_status"
  end

  create_table "parent_profiles", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "verified_parent_phone_e164", limit: 20, null: false
    t.index ["user_id"], name: "index_parent_profiles_on_user_id", unique: true
    t.index ["verified_parent_phone_e164"], name: "index_parent_profiles_on_verified_parent_phone_e164"
  end

  create_table "student_enrollments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "academic_year_id", null: false
    t.datetime "created_at", null: false
    t.datetime "enrolled_at", null: false
    t.bigint "grade_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "student_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["academic_year_id", "grade_id", "status", "student_profile_id"], name: "idx_year_grade_roster"
    t.index ["grade_id"], name: "index_student_enrollments_on_grade_id"
    t.index ["student_profile_id", "academic_year_id"], name: "idx_student_year_unique", unique: true
    t.check_constraint "`status` between 0 and 2", name: "chk_student_enrollments_status"
  end

  create_table "student_parent_links", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "linked_at", null: false
    t.bigint "parent_profile_id", null: false
    t.integer "relation", default: 3, null: false
    t.integer "status", default: 0, null: false
    t.bigint "student_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_profile_id", "status", "student_profile_id"], name: "idx_parent_active_students"
    t.index ["student_profile_id", "parent_profile_id"], name: "idx_student_parent_unique", unique: true
    t.check_constraint "`relation` between 0 and 3", name: "chk_student_parent_links_relation"
    t.check_constraint "`status` between 0 and 1", name: "chk_student_parent_links_status"
  end

  create_table "student_profiles", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "birth_date", null: false
    t.datetime "created_at", null: false
    t.string "governorate"
    t.text "notes"
    t.string "parent_phone_e164", limit: 20, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["parent_phone_e164"], name: "index_student_profiles_on_parent_phone_e164"
    t.index ["user_id"], name: "index_student_profiles_on_user_id", unique: true
  end

  create_table "support_request_actions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "action", null: false
    t.datetime "created_at", null: false
    t.text "note"
    t.bigint "reviewer_user_id", null: false
    t.bigint "support_request_id", null: false
    t.datetime "updated_at", null: false
    t.index ["reviewer_user_id"], name: "index_support_request_actions_on_reviewer_user_id"
    t.index ["support_request_id", "created_at"], name: "idx_on_support_request_id_created_at_cfe125deac"
    t.check_constraint "`action` between 0 and 2", name: "chk_support_request_actions_action"
  end

  create_table "support_requests", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "payload"
    t.text "reason"
    t.integer "request_type", null: false
    t.bigint "requester_user_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "student_profile_id"
    t.datetime "updated_at", null: false
    t.index ["requester_user_id", "created_at"], name: "index_support_requests_on_requester_user_id_and_created_at"
    t.index ["status", "request_type", "created_at"], name: "idx_on_status_request_type_created_at_4ca9d668d8"
    t.index ["student_profile_id", "status", "created_at"], name: "idx_student_support_state"
    t.check_constraint "`request_type` between 0 and 2", name: "chk_support_requests_request_type"
    t.check_constraint "`status` between 0 and 3", name: "chk_support_requests_status"
  end

  create_table "user_sessions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "device_registration_id"
    t.datetime "ended_at"
    t.datetime "last_seen_at", null: false
    t.string "session_token_digest", limit: 64, null: false
    t.datetime "started_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["device_registration_id"], name: "index_user_sessions_on_device_registration_id"
    t.index ["session_token_digest"], name: "index_user_sessions_on_session_token_digest", unique: true
    t.index ["status", "last_seen_at"], name: "index_user_sessions_on_status_and_last_seen_at"
    t.index ["user_id", "status", "last_seen_at"], name: "index_user_sessions_on_user_id_and_status_and_last_seen_at"
    t.check_constraint "`status` between 0 and 2", name: "chk_user_sessions_status"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_login_at"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "phone_display"
    t.string "phone_e164", limit: 20, null: false
    t.datetime "phone_verified_at"
    t.integer "role", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["phone_e164"], name: "index_users_on_phone_e164", unique: true
    t.index ["role", "status"], name: "index_users_on_role_and_status"
    t.index ["status", "last_login_at"], name: "index_users_on_status_and_last_login_at"
    t.check_constraint "`role` between 0 and 3", name: "chk_users_role"
    t.check_constraint "`status` between 0 and 2", name: "chk_users_status"
  end

  create_table "video_assets", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.json "available_qualities"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.integer "duration_seconds"
    t.bigint "lecture_id", null: false
    t.string "original_file_key", null: false
    t.integer "processing_status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.boolean "watermark_enabled", default: true, null: false
    t.index ["created_by_user_id"], name: "index_video_assets_on_created_by_user_id"
    t.index ["lecture_id", "processing_status"], name: "index_video_assets_on_lecture_id_and_processing_status"
    t.check_constraint "(`duration_seconds` is null) or (`duration_seconds` > 0)", name: "chk_video_asset_duration"
    t.check_constraint "`processing_status` between 0 and 3", name: "chk_video_assets_processing_status"
  end

  create_table "video_variants", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_key", null: false
    t.string "quality", null: false
    t.bigint "size_bytes"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_asset_id", null: false
    t.index ["video_asset_id", "quality"], name: "index_video_variants_on_video_asset_id_and_quality", unique: true
    t.check_constraint "(`size_bytes` is null) or (`size_bytes` > 0)", name: "chk_video_variant_size"
    t.check_constraint "`status` between 0 and 2", name: "chk_video_variants_status"
  end

  add_foreign_key "academic_years", "academic_years", column: "copied_from_year_id"
  add_foreign_key "activation_code_batches", "academic_years"
  add_foreign_key "activation_code_batches", "grades"
  add_foreign_key "activation_code_batches", "lessons"
  add_foreign_key "activation_code_batches", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "activation_codes", "activation_code_batches"
  add_foreign_key "activation_codes", "student_profiles", column: "redeemed_by_student_profile_id"
  add_foreign_key "announcement_targets", "announcements", on_delete: :cascade
  add_foreign_key "announcement_targets", "grades"
  add_foreign_key "announcement_targets", "users"
  add_foreign_key "announcements", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "assistant_permissions", "assistant_profiles", on_delete: :cascade
  add_foreign_key "assistant_profiles", "users"
  add_foreign_key "audit_logs", "users", column: "actor_user_id", on_delete: :nullify
  add_foreign_key "branches", "academic_years"
  add_foreign_key "branches", "grades"
  add_foreign_key "chapters", "branches"
  add_foreign_key "device_registrations", "student_profiles"
  add_foreign_key "exam_answers", "exam_attempts"
  add_foreign_key "exam_answers", "exam_choices", column: "selected_choice_id"
  add_foreign_key "exam_answers", "exam_questions"
  add_foreign_key "exam_attempts", "exams"
  add_foreign_key "exam_attempts", "student_profiles"
  add_foreign_key "exam_choices", "exam_questions"
  add_foreign_key "exam_questions", "exams"
  add_foreign_key "exams", "academic_years"
  add_foreign_key "exams", "branches"
  add_foreign_key "exams", "chapters"
  add_foreign_key "exams", "grades"
  add_foreign_key "exams", "lessons"
  add_foreign_key "exams", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "lecture_watch_events", "device_registrations"
  add_foreign_key "lecture_watch_events", "lectures"
  add_foreign_key "lecture_watch_events", "student_profiles"
  add_foreign_key "lectures", "lessons"
  add_foreign_key "lesson_access_grants", "academic_years"
  add_foreign_key "lesson_access_grants", "activation_codes"
  add_foreign_key "lesson_access_grants", "lessons"
  add_foreign_key "lesson_access_grants", "student_profiles"
  add_foreign_key "lessons", "chapters"
  add_foreign_key "lessons", "exams", column: "required_exam_id"
  add_foreign_key "otp_verifications", "users", on_delete: :nullify
  add_foreign_key "parent_phone_changes", "otp_verifications"
  add_foreign_key "parent_phone_changes", "student_profiles"
  add_foreign_key "parent_phone_changes", "users", column: "requested_by_user_id"
  add_foreign_key "parent_profiles", "users"
  add_foreign_key "student_enrollments", "academic_years"
  add_foreign_key "student_enrollments", "grades"
  add_foreign_key "student_enrollments", "student_profiles"
  add_foreign_key "student_parent_links", "parent_profiles"
  add_foreign_key "student_parent_links", "student_profiles"
  add_foreign_key "student_profiles", "users"
  add_foreign_key "support_request_actions", "support_requests", on_delete: :cascade
  add_foreign_key "support_request_actions", "users", column: "reviewer_user_id"
  add_foreign_key "support_requests", "student_profiles"
  add_foreign_key "support_requests", "users", column: "requester_user_id"
  add_foreign_key "user_sessions", "device_registrations"
  add_foreign_key "user_sessions", "users"
  add_foreign_key "video_assets", "lectures"
  add_foreign_key "video_assets", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "video_variants", "video_assets", on_delete: :cascade
end
