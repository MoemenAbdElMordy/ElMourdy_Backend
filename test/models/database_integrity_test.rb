require "test_helper"

class DatabaseIntegrityTest < ActiveSupport::TestCase
  test "database rejects an invalid academic year range" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      AcademicYear.insert_all!([ {
        name: "Invalid Year",
        starts_on: Date.new(2027, 1, 1),
        ends_on: Date.new(2026, 1, 1),
        status: 0,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end

    assert_match "chk_academic_year_dates", error.message
  end

  test "database rejects an exam with conflicting scope references" do
    year, grade, branch, chapter, lesson = create_curriculum

    error = assert_raises(ActiveRecord::StatementInvalid) do
      Exam.insert_all!([ {
        title: "Invalid Exam",
        scope_type: Exam.scope_types[:lesson],
        lesson_id: lesson.id,
        chapter_id: chapter.id,
        branch_id: branch.id,
        academic_year_id: year.id,
        grade_id: grade.id,
        duration_minutes: 30,
        max_attempts: 3,
        pass_percent: 50,
        risk_from_percent: 50,
        risk_to_percent: 60,
        shuffle_questions: false,
        shuffle_choices: false,
        attempt_form_mode: 0,
        show_result_immediately: true,
        status: 0,
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end

    assert_match "chk_exam_scope", error.message
  end

  test "database cascades owned assistant permissions" do
    assistant = create_user(role: :assistant)
    profile = AssistantProfile.create!(user: assistant, title: "Operations")
    profile.assistant_permissions.create!(permission_key: "manage_students")

    profile.delete

    assert_equal 0, AssistantPermission.count
  end
end
