module Api
  class ExamsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_management!, only: %i[create update]

    def index
      exams = if current_user.student?
        enrollment = current_user.student_profile.student_enrollments.active.order(enrolled_at: :desc).first
        enrollment ? Exam.published.where(academic_year: enrollment.academic_year, grade: enrollment.grade) : Exam.none
      elsif current_user.parent?
        Exam.none
      else
        permission = params[:assessment_type].to_s == "homework" ? "manage_homeworks" : "manage_exams"
        require_teacher_or_assistant_permission!(permission)
        return if performed?

        Exam.all
      end
      exams = exams.where(grade_id: params[:grade_id]) if params[:grade_id].present?
      exams = exams.where(lesson_id: params[:lesson_id]) if params[:lesson_id].present?
      exams = exams.where(assessment_type: params[:assessment_type]) if params[:assessment_type].present?
      exams, pagination = paginate(exams.includes(:exam_questions, :exam_attempts).order(created_at: :desc))
      render json: { exams: exams.map { |exam| serialize_exam(exam) }, pagination: }
    end

    def show
      exam = Exam.includes(exam_questions: :exam_choices).find(params[:id])
      authorize_exam_access!(exam)
      return if performed?

      render json: { exam: serialize_exam(exam, include_questions: true, reveal_answers: !current_user.student?) }
    end

    def create
      exam = Exam.transaction do
        record = Exam.new(exam_attributes.except(:questions))
        record.created_by_user = current_user
        record.save!
        replace_questions!(record, exam_attributes[:questions])
        ensure_publishable!(record)
        record
      end
      render json: { exam: serialize_exam(exam.reload, include_questions: true, reveal_answers: true) }, status: :created
    end

    def update
      exam = Exam.find(params[:id])
      exam = Exam.transaction do
        attributes = exam_attributes
        if attributes[:questions].present? && exam.exam_attempts.exists?
          raise ApplicationService::Error, "Questions cannot be changed after students start this exam"
        end
        exam.update!(attributes.except(:questions))
        replace_questions!(exam, attributes[:questions]) if attributes.key?(:questions)
        ensure_publishable!(exam)
        exam
      end
      render json: { exam: serialize_exam(exam.reload, include_questions: true, reveal_answers: true) }
    end

    private

    def authorize_management!
      type = params.dig(:exam, :assessment_type) || (params[:id] && Exam.where(id: params[:id]).pick(:assessment_type)) || params[:assessment_type]
      permission = type.to_s == "homework" ? "manage_homeworks" : "manage_exams"
      require_teacher_or_assistant_permission!(permission)
    end

    def authorize_exam_access!(exam)
      return authorize_management! unless current_user.student?

      enrollment = current_user.student_profile.student_enrollments.active.find_by(
        academic_year_id: exam.academic_year_id, grade_id: exam.grade_id
      )
      render_forbidden unless exam.published? && enrollment
    end

    def exam_attributes
      params.require(:exam).permit(
        :title, :scope_type, :lesson_id, :chapter_id, :branch_id, :academic_year_id, :grade_id,
        :duration_minutes, :max_attempts, :pass_percent, :risk_from_percent, :risk_to_percent,
        :attempt_form_mode, :show_result_immediately, :shuffle_questions, :shuffle_choices, :status,
        :assessment_type, :show_answers_after_submission, :correct_after_each_answer,
        questions: [ :body, :explanation, :points, { choices: %i[body is_correct] } ]
      )
    end

    def replace_questions!(exam, questions)
      return if questions.nil?

      ExamChoice.where(exam_question_id: exam.exam_questions.select(:id)).delete_all
      exam.exam_questions.destroy_all
      questions.each_with_index do |question_attributes, question_index|
        question = exam.exam_questions.create!(question_attributes.except(:choices).merge(position: question_index + 1))
        Array(question_attributes[:choices]).each_with_index do |choice_attributes, choice_index|
          question.exam_choices.create!(choice_attributes.merge(position: choice_index + 1))
        end
      end
    end

    def ensure_publishable!(exam)
      return unless exam.published?

      questions = exam.exam_questions.includes(:exam_choices)
      valid = questions.any? && questions.all? do |question|
        question.exam_choices.size >= 2 && question.exam_choices.count(&:is_correct?) == 1
      end
      raise ApplicationService::Error, "A published exam needs questions with one correct choice each" unless valid
    end

    def serialize_exam(exam, include_questions: false, reveal_answers: false)
      payload = {
        id: exam.id, title: exam.title, scope_type: exam.scope_type, lesson_id: exam.lesson_id,
        chapter_id: exam.chapter_id, branch_id: exam.branch_id, academic_year_id: exam.academic_year_id,
        grade_id: exam.grade_id, duration_minutes: exam.duration_minutes, max_attempts: exam.max_attempts,
        pass_percent: exam.pass_percent, risk_from_percent: exam.risk_from_percent,
        risk_to_percent: exam.risk_to_percent, attempt_form_mode: exam.attempt_form_mode,
        assessment_type: exam.assessment_type, show_result_immediately: exam.show_result_immediately,
        show_answers_after_submission: exam.show_answers_after_submission,
        correct_after_each_answer: exam.correct_after_each_answer, shuffle_questions: exam.shuffle_questions,
        shuffle_choices: exam.shuffle_choices, status: exam.status, questions_count: exam.exam_questions.size,
        attempts_count: exam.exam_attempts.size
      }
      payload[:questions] = exam.exam_questions.order(:position).map do |question|
        choices = question.exam_choices.order(:position)
        choices = choices.shuffle if current_user.student? && exam.shuffle_choices?
        {
          id: question.id, body: question.body, explanation: reveal_answers ? question.explanation : nil,
          points: question.points, choices: choices.map { |choice| { id: choice.id, body: choice.body }.tap { |item| item[:is_correct] = choice.is_correct if reveal_answers } }
        }
      end if include_questions
      payload
    end
  end
end
