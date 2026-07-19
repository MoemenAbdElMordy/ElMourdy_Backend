module ExamAttempts
  class Start < ApplicationService
    def self.call(exam:, student_profile:, at: Time.current)
      new(exam:, student_profile:, at:).call
    end

    def initialize(exam:, student_profile:, at:)
      @exam = exam
      @student_profile = student_profile
      @at = at
    end

    def call
      ExamAttempt.transaction do
        @student_profile.lock!
        submitted_count = ExamAttempt.where(exam: @exam, student_profile: @student_profile).count
        raise Error, "Maximum exam attempts reached" if submitted_count >= @exam.max_attempts

        ExamAttempt.create!(
          exam: @exam,
          student_profile: @student_profile,
          attempt_number: submitted_count + 1,
          started_at: @at,
          status: :in_progress,
          question_order: question_order
        )
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    private

    def question_order
      ids = @exam.exam_questions.order(:position).pluck(:id)
      @exam.shuffle_questions? ? ids.shuffle : ids
    end
  end
end
