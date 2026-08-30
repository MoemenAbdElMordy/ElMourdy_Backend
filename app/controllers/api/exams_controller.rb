module Api
  class ExamsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_management!, only: %i[create update]

    def index
      exams = if current_user.student?
        enrollment = current_user.student_profile.student_enrollments.active.order(enrolled_at: :desc).first
        enrollment ? student_visible_exams(enrollment) : Exam.none
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
        attributes = exam_attributes
        record = Exam.new(attributes.except(:questions, :grade_ids))
        record.grade_id = selected_grade_ids(attributes).first if record.assessment_type_homework?
        record.created_by_user = current_user
        record.save!
        sync_grade_assignments!(record, selected_grade_ids(attributes))
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
        exam.grade_id = selected_grade_ids(attributes).first if attributes[:assessment_type].to_s == "homework"
        exam.update!(attributes.except(:questions, :grade_ids))
        sync_grade_assignments!(exam, selected_grade_ids(attributes))
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
        academic_year_id: exam.academic_year_id
      )
      render_forbidden unless exam.published? && enrollment && exam_visible_for_grade?(exam, enrollment.grade_id)
    end

    def exam_attributes
      params.require(:exam).permit(
        :title, :scope_type, :lesson_id, :chapter_id, :branch_id, :academic_year_id, :grade_id,
        :duration_minutes, :max_attempts, :pass_percent, :risk_from_percent, :risk_to_percent,
        :attempt_form_mode, :show_result_immediately, :shuffle_questions, :shuffle_choices, :status,
        :assessment_type, :show_answers_after_submission, :correct_after_each_answer,
        grade_ids: [],
        questions: [ :body, :explanation, :points, { choices: %i[body is_correct] } ]
      )
    end

    def student_visible_exams(enrollment)
      Exam.published
        .left_outer_joins(:exam_grade_assignments)
        .where(academic_year: enrollment.academic_year)
        .where("exams.grade_id = :grade_id OR exam_grade_assignments.grade_id = :grade_id", grade_id: enrollment.grade_id)
        .distinct
    end

    def exam_visible_for_grade?(exam, grade_id)
      exam.grade_id == grade_id || exam.exam_grade_assignments.exists?(grade_id:)
    end

    def selected_grade_ids(attributes)
      ids = Array(attributes[:grade_ids]).reject(&:blank?).map(&:to_i)
      ids = [ attributes[:grade_id].to_i ] if ids.empty? && attributes[:grade_id].present?
      ids.uniq
    end

    def sync_grade_assignments!(exam, grade_ids)
      unless exam.assessment_type_homework?
        exam.exam_grade_assignments.delete_all
        return
      end

      valid_grade_ids = Grade.where(id: grade_ids).pluck(:id)
      raise ApplicationService::Error, "At least one grade is required for a homework" if valid_grade_ids.empty?

      exam.exam_grade_assignments.where.not(grade_id: valid_grade_ids).delete_all
      valid_grade_ids.each do |grade_id|
        exam.exam_grade_assignments.find_or_create_by!(grade_id:)
      end
    end

    def replace_questions!(exam, questions)
      return if questions.nil?

      ExamChoice.where(exam_question_id: exam.exam_questions.select(:id)).delete_all
      exam.exam_questions.destroy_all
      questions.each_with_index do |question_attributes, question_index|
        question_payload = question_attributes.except(:choices).to_h
        question_payload["body"] = sanitized_rich_text(question_payload["body"])
        question_payload["explanation"] = sanitized_rich_text(question_payload["explanation"])
        question = exam.exam_questions.create!(question_payload.merge(position: question_index + 1))
        Array(question_attributes[:choices]).each_with_index do |choice_attributes, choice_index|
          choice_payload = choice_attributes.to_h
          choice_payload["body"] = sanitized_rich_text(choice_payload["body"])
          question.exam_choices.create!(choice_payload.merge(position: choice_index + 1))
        end
      end
    end

    def sanitized_rich_text(value)
      ActionController::Base.helpers.sanitize(value.to_s, tags: %w[u], attributes: [])
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
      grade_ids = assigned_grade_ids_for(exam)
      payload = {
        id: exam.id, title: exam.title, scope_type: exam.scope_type, lesson_id: exam.lesson_id,
        chapter_id: exam.chapter_id, branch_id: exam.branch_id, academic_year_id: exam.academic_year_id,
        grade_id: exam.grade_id, grade_ids:, duration_minutes: exam.duration_minutes, max_attempts: exam.max_attempts,
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

    def assigned_grade_ids_for(exam)
      ids = exam.exam_grade_assignments.loaded? ? exam.exam_grade_assignments.map(&:grade_id) : exam.exam_grade_assignments.pluck(:grade_id)
      ids.presence || [ exam.grade_id ]
    end
  end
end
