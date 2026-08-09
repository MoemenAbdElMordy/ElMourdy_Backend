module Api
  class ExamAttemptsController < ApplicationController
    before_action :authenticate_user!

    def index
      attempts = attempts_for_current_user
      return if performed?

      attempts = attempts.where(exam_id: params[:exam_id]) if params[:exam_id].present?
      attempts = attempts.where(student_profile_id: params[:student_profile_id]) if params[:student_profile_id].present?
      render json: { attempts: attempts.includes(:exam, student_profile: :user).recent.map { |attempt| serialize_summary(attempt) } }
    end

    def show
      attempt = ExamAttempt.includes(exam: { exam_questions: :exam_choices }, exam_answers: :selected_choice).find(params[:id])
      authorize_attempt!(attempt)
      return if performed?

      render json: { attempt: serialize_attempt(attempt) }
    end

    def create
      return render_forbidden unless current_user.student?

      exam = Exam.published.find(params[:exam_id])
      enrollment = current_user.student_profile.student_enrollments.active.find_by(
        academic_year_id: exam.academic_year_id, grade_id: exam.grade_id
      )
      return render_forbidden unless enrollment

      attempt = ExamAttempts::Start.call(exam:, student_profile: current_user.student_profile)
      render json: { attempt: serialize_attempt(attempt.reload) }, status: :created
    end

    def submit
      return render_forbidden unless current_user.student?

      attempt = current_user.student_profile.exam_attempts.find(params[:id])
      answers = params.require(:answers).map { |answer| answer.permit(:question_id, :choice_id).to_h.symbolize_keys }
      ExamAttempts::Submit.call(attempt:, answers:)
      render json: { attempt: serialize_attempt(attempt.reload) }
    end

    private

    def attempts_for_current_user
      if current_user.student?
        current_user.student_profile.exam_attempts
      elsif current_user.parent?
        student_ids = current_user.parent_profile.student_parent_links.active.pluck(:student_profile_id)
        ExamAttempt.where(student_profile_id: student_ids)
      else
        require_teacher_or_assistant_permission!("manage_exams")
        ExamAttempt.all unless performed?
      end
    end

    def authorize_attempt!(attempt)
      allowed = if current_user.student?
        attempt.student_profile_id == current_user.student_profile.id
      elsif current_user.parent?
        current_user.parent_profile.student_parent_links.active.exists?(student_profile_id: attempt.student_profile_id)
      else
        require_teacher_or_assistant_permission!("manage_exams")
        !performed?
      end
      render_forbidden unless allowed || performed?
    end

    def serialize_summary(attempt)
      {
        id: attempt.id, exam_id: attempt.exam_id, exam_title: attempt.exam.title,
        student_profile_id: attempt.student_profile_id, student_name: attempt.student_profile.user.name,
        attempt_number: attempt.attempt_number, status: attempt.status, started_at: attempt.started_at,
        submitted_at: attempt.submitted_at, score_points: attempt.score_points, max_points: attempt.max_points,
        percent: attempt.percent, result_status: attempt.result_status
      }
    end

    def serialize_attempt(attempt)
      payload = serialize_summary(attempt)
      ordered_ids = Array(attempt.question_order).map(&:to_i)
      questions = attempt.exam.exam_questions.includes(:exam_choices).index_by(&:id)
      payload[:duration_minutes] = attempt.exam.duration_minutes
      payload[:questions] = ordered_ids.filter_map do |question_id|
        question = questions[question_id]
        next unless question

        answer = attempt.exam_answers.find { |candidate| candidate.exam_question_id == question.id }
        item = {
          id: question.id, body: question.body, points: question.points,
          choices: question.exam_choices.order(:position).map { |choice| { id: choice.id, body: choice.body } },
          selected_choice_id: answer&.selected_choice_id
        }
        if attempt.submitted? && attempt.exam.show_result_immediately?
          item[:is_correct] = answer&.is_correct || false
          item[:correct_choice_id] = question.exam_choices.find(&:is_correct?)&.id
          item[:explanation] = question.explanation
        end
        item
      end
      payload
    end
  end
end
