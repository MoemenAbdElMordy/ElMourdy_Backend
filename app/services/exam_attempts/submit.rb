module ExamAttempts
  class Submit < ApplicationService
    def self.call(attempt:, answers:, at: Time.current)
      new(attempt:, answers:, at:).call
    end

    def initialize(attempt:, answers:, at:)
      @attempt = attempt
      @answers = answers
      @at = at
    end

    def call
      ExamAttempt.transaction do
        @attempt.lock!
        raise Error, "This exam attempt has already ended" unless @attempt.in_progress?

        if @at > @attempt.started_at + @attempt.exam.duration_minutes.minutes
          @attempt.update!(status: :expired)
          raise Error, "The exam time has expired"
        end

        questions = @attempt.exam.exam_questions.includes(:exam_choices).index_by(&:id)
        answer_map = Array(@answers).index_by { |answer| answer.fetch(:question_id).to_i }
        unknown_ids = answer_map.keys - questions.keys
        raise Error, "An answer contains a question outside this exam" if unknown_ids.any?

        questions.each_value do |question|
          choice_id = answer_map.dig(question.id, :choice_id)&.to_i
          choice = question.exam_choices.find { |candidate| candidate.id == choice_id }
          correct = choice&.is_correct? || false
          @attempt.exam_answers.create!(
            exam_question: question,
            selected_choice: choice,
            is_correct: correct,
            points_awarded: correct ? question.points : 0
          )
        end

        max_points = questions.values.sum(&:points)
        score_points = @attempt.exam_answers.sum(:points_awarded)
        percent = (score_points * 100 / max_points).round(2)
        result_status = if percent >= @attempt.exam.pass_percent
          :passed
        elsif percent.between?(@attempt.exam.risk_from_percent, @attempt.exam.risk_to_percent)
          :risk
        else
          :failed
        end

        @attempt.update!(
          status: :submitted,
          submitted_at: @at,
          score_points:,
          max_points:,
          percent:,
          result_status:
        )
        @attempt
      end
    end
  end
end
