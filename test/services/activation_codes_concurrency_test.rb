require "test_helper"

class ActivationCodesConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "only one student can redeem the same code concurrently" do
    first_student = create_student
    second_student = create_student
    year, grade, branch, chapter, lesson = create_curriculum
    @student_ids = [ first_student.id, second_student.id ]
    @user_ids = [ first_student.user_id, second_student.user_id ]
    @curriculum_ids = { year: year.id, grade: grade.id, branch: branch.id, chapter: chapter.id, lesson: lesson.id }
    [ first_student, second_student ].each do |student|
      StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, status: :active, enrolled_at: Time.current)
    end
    raw_code = "ELM-CONC-TEST"
    batch = ActivationCodeBatch.create!(lesson:, academic_year: year, grade:, name: "Concurrent Batch", quantity: 1, expires_on: Date.current + 30.days)
    @batch_id = batch.id
    batch.activation_codes.create!(code_digest: Security::DigestValue.call(raw_code), status: :unused)

    ready = Queue.new
    release = Queue.new
    results = Queue.new
    threads = [ first_student.id, second_student.id ].map do |student_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          release.pop
          student = StudentProfile.find(student_id)
          results << ActivationCodes::Redeem.call(raw_code:, student_profile: student)
        rescue ApplicationService::Error => error
          results << error
        end
      end
    end
    2.times { ready.pop }
    2.times { release << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }

    assert_equal 1, outcomes.count { |outcome| outcome.is_a?(LessonAccessGrant) }
    assert_equal 1, outcomes.count { |outcome| outcome.is_a?(ApplicationService::Error) }
    assert_equal 1, LessonAccessGrant.where(lesson: lesson).count
    assert ActivationCode.find_by!(activation_code_batch: batch).redeemed?
  ensure
    cleanup_records
  end

  private

  def cleanup_records
    return unless @curriculum_ids

    LessonAccessGrant.where(lesson_id: @curriculum_ids[:lesson]).delete_all
    ActivationCode.where(activation_code_batch_id: @batch_id).delete_all
    ActivationCodeBatch.where(id: @batch_id).delete_all
    StudentEnrollment.where(student_profile_id: @student_ids).delete_all
    StudentProfile.where(id: @student_ids).delete_all
    User.where(id: @user_ids).delete_all
    Lesson.where(id: @curriculum_ids[:lesson]).delete_all
    Chapter.where(id: @curriculum_ids[:chapter]).delete_all
    Branch.where(id: @curriculum_ids[:branch]).delete_all
    AcademicYear.where(id: @curriculum_ids[:year]).delete_all
    Grade.where(id: @curriculum_ids[:grade]).delete_all
  end
end
