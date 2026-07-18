class CreateElMourdyCoreSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.integer :role, null: false
      t.string :name, null: false
      t.string :phone_e164, limit: 20, null: false
      t.string :phone_display
      t.string :password_digest, null: false
      t.integer :status, null: false, default: 0
      t.datetime :phone_verified_at
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :users, :phone_e164, unique: true
    add_index :users, %i[role status]
    add_index :users, %i[status last_login_at]

    create_table :student_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.date :birth_date, null: false
      t.string :parent_phone_e164, limit: 20, null: false
      t.string :governorate
      t.text :notes
      t.timestamps
    end
    add_index :student_profiles, :parent_phone_e164

    create_table :parent_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :verified_parent_phone_e164, limit: 20, null: false
      t.timestamps
    end
    add_index :parent_profiles, :verified_parent_phone_e164

    create_table :assistant_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :title
      t.boolean :can_login, null: false, default: true
      t.timestamps
    end

    create_table :assistant_permissions do |t|
      t.references :assistant_profile, null: false, foreign_key: true, index: false
      t.string :permission_key, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :assistant_permissions, %i[assistant_profile_id permission_key], unique: true, name: "idx_assistant_permissions_unique"

    create_table :student_parent_links do |t|
      t.references :student_profile, null: false, foreign_key: true, index: false
      t.references :parent_profile, null: false, foreign_key: true, index: false
      t.integer :relation, null: false, default: 3
      t.integer :status, null: false, default: 0
      t.datetime :linked_at, null: false
      t.timestamps
    end
    add_index :student_parent_links, %i[student_profile_id parent_profile_id], unique: true, name: "idx_student_parent_unique"
    add_index :student_parent_links, %i[parent_profile_id status student_profile_id], name: "idx_parent_active_students"

    create_table :academic_years do |t|
      t.string :name, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :status, null: false, default: 0
      t.references :copied_from_year, foreign_key: { to_table: :academic_years }
      t.timestamps
    end
    add_index :academic_years, :name, unique: true
    add_index :academic_years, %i[status starts_on]

    create_table :grades do |t|
      t.string :name, null: false
      t.integer :level, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :grades, :level, unique: true
    add_index :grades, %i[active level]

    create_table :student_enrollments do |t|
      t.references :student_profile, null: false, foreign_key: true, index: false
      t.references :academic_year, null: false, foreign_key: true, index: false
      t.references :grade, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :enrolled_at, null: false
      t.timestamps
    end
    add_index :student_enrollments, %i[student_profile_id academic_year_id], unique: true, name: "idx_student_year_unique"
    add_index :student_enrollments, %i[academic_year_id grade_id status student_profile_id], name: "idx_year_grade_roster"

    create_table :branches do |t|
      t.references :academic_year, null: false, foreign_key: true, index: false
      t.references :grade, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :position, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :branches, %i[academic_year_id grade_id position], unique: true, name: "idx_branch_position_unique"
    add_index :branches, %i[academic_year_id grade_id status position], name: "idx_published_branches"

    create_table :chapters do |t|
      t.references :branch, null: false, foreign_key: true, index: false
      t.string :title, null: false
      t.integer :position, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :chapters, %i[branch_id position], unique: true
    add_index :chapters, %i[branch_id status position]

    create_table :lessons do |t|
      t.references :chapter, null: false, foreign_key: true, index: false
      t.string :title, null: false
      t.integer :position, null: false
      t.boolean :is_free, null: false, default: false
      t.boolean :requires_exam_pass, null: false, default: false
      t.integer :pass_required_percent
      t.datetime :publish_at
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :lessons, %i[chapter_id position], unique: true
    add_index :lessons, %i[chapter_id status publish_at position], name: "idx_published_lessons"

    create_table :lectures do |t|
      t.references :lesson, null: false, foreign_key: true, index: false
      t.string :title, null: false
      t.integer :position, null: false
      t.integer :duration_seconds
      t.boolean :is_free, null: false, default: false
      t.datetime :publish_at
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :lectures, %i[lesson_id position], unique: true
    add_index :lectures, %i[lesson_id status publish_at position], name: "idx_published_lectures"

    create_table :video_assets do |t|
      t.references :lecture, null: false, foreign_key: true, index: false
      t.string :original_file_key, null: false
      t.integer :processing_status, null: false, default: 0
      t.integer :duration_seconds
      t.json :available_qualities
      t.boolean :watermark_enabled, null: false, default: true
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :video_assets, %i[lecture_id processing_status]

    create_table :video_variants do |t|
      t.references :video_asset, null: false, foreign_key: true, index: false
      t.string :quality, null: false
      t.string :file_key, null: false
      t.integer :status, null: false, default: 0
      t.bigint :size_bytes
      t.timestamps
    end
    add_index :video_variants, %i[video_asset_id quality], unique: true

    create_table :exams do |t|
      t.string :title, null: false
      t.integer :scope_type, null: false
      t.references :lesson, foreign_key: true, index: false
      t.references :chapter, foreign_key: true, index: false
      t.references :branch, foreign_key: true, index: false
      t.references :academic_year, null: false, foreign_key: true, index: false
      t.references :grade, null: false, foreign_key: true
      t.integer :duration_minutes, null: false
      t.integer :max_attempts, null: false, default: 3
      t.integer :pass_percent, null: false, default: 50
      t.integer :risk_from_percent, null: false, default: 50
      t.integer :risk_to_percent, null: false, default: 60
      t.boolean :shuffle_questions, null: false, default: false
      t.boolean :shuffle_choices, null: false, default: false
      t.integer :attempt_form_mode, null: false, default: 0
      t.boolean :show_result_immediately, null: false, default: true
      t.integer :status, null: false, default: 0
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :exams, %i[academic_year_id grade_id status scope_type], name: "idx_exams_year_grade"
    add_index :exams, %i[lesson_id status]
    add_index :exams, %i[chapter_id status]
    add_index :exams, %i[branch_id status]

    add_reference :lessons, :required_exam, foreign_key: { to_table: :exams }

    create_table :exam_questions do |t|
      t.references :exam, null: false, foreign_key: true, index: false
      t.text :body, null: false
      t.text :explanation
      t.decimal :points, precision: 8, scale: 2, null: false, default: 1
      t.integer :position, null: false
      t.timestamps
    end
    add_index :exam_questions, %i[exam_id position], unique: true

    create_table :exam_choices do |t|
      t.references :exam_question, null: false, foreign_key: true, index: false
      t.text :body, null: false
      t.boolean :is_correct, null: false, default: false
      t.integer :position, null: false
      t.timestamps
    end
    add_index :exam_choices, %i[exam_question_id position], unique: true

    create_table :activation_code_batches do |t|
      t.references :lesson, null: false, foreign_key: true
      t.references :academic_year, null: false, foreign_key: true
      t.references :grade, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :quantity, null: false
      t.date :expires_on, null: false
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :activation_code_batches, %i[lesson_id academic_year_id grade_id deleted_at], name: "idx_code_batches_scope"

    create_table :activation_codes do |t|
      t.references :activation_code_batch, null: false, foreign_key: true, index: false
      t.string :code_digest, limit: 64, null: false
      t.text :code_ciphertext
      t.integer :status, null: false, default: 0
      t.references :redeemed_by_student_profile, foreign_key: { to_table: :student_profiles }, index: false
      t.datetime :redeemed_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :activation_codes, :code_digest, unique: true
    add_index :activation_codes, %i[activation_code_batch_id status id], name: "idx_codes_batch_status"
    add_index :activation_codes, %i[redeemed_by_student_profile_id redeemed_at], name: "idx_student_redemptions"

    create_table :lesson_access_grants do |t|
      t.references :student_profile, null: false, foreign_key: true, index: false
      t.references :lesson, null: false, foreign_key: true, index: false
      t.references :academic_year, null: false, foreign_key: true
      t.references :activation_code, foreign_key: true
      t.integer :source, null: false
      t.date :expires_on, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :lesson_access_grants, %i[student_profile_id lesson_id academic_year_id], unique: true, name: "idx_lesson_grant_unique"
    add_index :lesson_access_grants, %i[student_profile_id academic_year_id status expires_on], name: "idx_student_active_grants"
    add_index :lesson_access_grants, %i[lesson_id academic_year_id status], name: "idx_lesson_grant_report"

    create_table :exam_attempts do |t|
      t.references :exam, null: false, foreign_key: true, index: false
      t.references :student_profile, null: false, foreign_key: true, index: false
      t.integer :attempt_number, null: false
      t.datetime :started_at, null: false
      t.datetime :submitted_at
      t.decimal :score_points, precision: 10, scale: 2
      t.decimal :max_points, precision: 10, scale: 2
      t.decimal :percent, precision: 5, scale: 2
      t.integer :result_status
      t.integer :status, null: false, default: 0
      t.json :question_order
      t.timestamps
    end
    add_index :exam_attempts, %i[exam_id student_profile_id attempt_number], unique: true, name: "idx_exam_attempt_unique"
    add_index :exam_attempts, %i[student_profile_id submitted_at]
    add_index :exam_attempts, %i[exam_id status submitted_at]

    create_table :exam_answers do |t|
      t.references :exam_attempt, null: false, foreign_key: true, index: false
      t.references :exam_question, null: false, foreign_key: true
      t.references :selected_choice, foreign_key: { to_table: :exam_choices }
      t.boolean :is_correct
      t.decimal :points_awarded, precision: 8, scale: 2
      t.timestamps
    end
    add_index :exam_answers, %i[exam_attempt_id exam_question_id], unique: true, name: "idx_attempt_answer_unique"

    create_table :device_registrations do |t|
      t.references :student_profile, null: false, foreign_key: true, index: false
      t.string :device_fingerprint_digest, limit: 64, null: false
      t.string :device_name
      t.string :browser
      t.string :os
      t.string :ip_address, limit: 45
      t.text :user_agent
      t.integer :status, null: false, default: 0
      t.datetime :last_seen_at
      t.datetime :removed_at
      t.datetime :last_self_removed_at
      t.timestamps
    end
    add_index :device_registrations, %i[student_profile_id device_fingerprint_digest], unique: true, name: "idx_student_device_unique"
    add_index :device_registrations, %i[student_profile_id status last_seen_at], name: "idx_active_devices"

    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :device_registration, foreign_key: true
      t.string :session_token_digest, limit: 64, null: false
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :ended_at
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :user_sessions, :session_token_digest, unique: true
    add_index :user_sessions, %i[user_id status last_seen_at]
    add_index :user_sessions, %i[status last_seen_at]

    create_table :lecture_watch_events do |t|
      t.references :student_profile, null: false, foreign_key: true, index: false
      t.references :lecture, null: false, foreign_key: true, index: false
      t.references :device_registration, foreign_key: true
      t.datetime :started_at, null: false
      t.integer :last_position_seconds, null: false, default: 0
      t.datetime :completed_at
      t.string :ip_address, limit: 45
      t.text :user_agent
      t.timestamps
    end
    add_index :lecture_watch_events, %i[student_profile_id lecture_id started_at], name: "idx_student_lecture_watch"
    add_index :lecture_watch_events, %i[lecture_id started_at]

    create_table :otp_verifications do |t|
      t.references :user, foreign_key: true
      t.string :phone_e164, limit: 20, null: false
      t.integer :purpose, null: false
      t.string :code_digest, limit: 64, null: false
      t.integer :status, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :verified_at
      t.integer :attempts_count, null: false, default: 0
      t.json :metadata
      t.timestamps
    end
    add_index :otp_verifications, %i[phone_e164 purpose status created_at], name: "idx_latest_otp"
    add_index :otp_verifications, %i[status expires_at]

    create_table :support_requests do |t|
      t.integer :request_type, null: false
      t.references :requester_user, null: false, foreign_key: { to_table: :users }, index: false
      t.references :student_profile, foreign_key: true, index: false
      t.integer :status, null: false, default: 0
      t.text :reason
      t.json :payload
      t.timestamps
    end
    add_index :support_requests, %i[status request_type created_at]
    add_index :support_requests, %i[requester_user_id created_at]
    add_index :support_requests, %i[student_profile_id status created_at], name: "idx_student_support_state"

    create_table :support_request_actions do |t|
      t.references :support_request, null: false, foreign_key: true, index: false
      t.references :reviewer_user, null: false, foreign_key: { to_table: :users }
      t.integer :action, null: false
      t.text :note
      t.timestamps
    end
    add_index :support_request_actions, %i[support_request_id created_at]

    create_table :parent_phone_changes do |t|
      t.references :student_profile, null: false, foreign_key: true, index: false
      t.string :old_phone_e164, limit: 20, null: false
      t.string :new_phone_e164, limit: 20, null: false
      t.references :requested_by_user, null: false, foreign_key: { to_table: :users }
      t.references :otp_verification, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :applied_at
      t.timestamps
    end
    add_index :parent_phone_changes, %i[student_profile_id status created_at], name: "idx_parent_phone_change_state"

    create_table :announcements do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.datetime :publish_at
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :announcements, %i[status publish_at]

    create_table :announcement_targets do |t|
      t.references :announcement, null: false, foreign_key: true
      t.integer :target_type, null: false
      t.references :grade, foreign_key: true
      t.references :user, foreign_key: true
      t.timestamps
    end
    add_index :announcement_targets, %i[target_type grade_id announcement_id], name: "idx_grade_announcement_targets"
    add_index :announcement_targets, %i[target_type user_id announcement_id], name: "idx_user_announcement_targets"

    create_table :audit_logs do |t|
      t.references :actor_user, foreign_key: { to_table: :users }, index: false
      t.string :action, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.json :metadata
      t.string :ip_address, limit: 45
      t.datetime :created_at, null: false
    end
    add_index :audit_logs, %i[actor_user_id created_at]
    add_index :audit_logs, %i[target_type target_id created_at], name: "idx_audit_target"
    add_index :audit_logs, %i[action created_at]
  end
end
