require "csv"

module Api
  class ActivationCodeBatchesController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_codes") }

    def index
      batches = ActivationCodeBatch.includes(:lesson, :academic_year, :grade, activation_codes: [ :redeemed_by_student_profile, { lecture_access_grant: :lecture } ])
        .where(deleted_at: nil).order(created_at: :desc)
      batches, pagination = paginate(batches)
      render json: { batches: batches.map { |batch| serialize_batch(batch, include_codes: true) }, pagination: }
    end

    def create
      result = ActivationCodes::GenerateBatch.call(attributes: batch_params.to_h.symbolize_keys, created_by_user: current_user)
      render json: {
        batch: serialize_batch(result.batch.reload, include_codes: true),
        generated_codes: result.raw_codes
      }, status: :created
    end

    def export
      batch = ActivationCodeBatch.includes(:lesson, :academic_year, :grade, activation_codes: [ :redeemed_by_student_profile, { lecture_access_grant: :lecture } ]).find(params[:id])
      if params[:format] == "docx"
        codes = batch.activation_codes.order(:id).map { |code| serialize_code(code) }
        document = Documents::ReportDocuments.activation_codes(batch, codes)
        return send_data document, filename: "activation-codes-#{batch.id}.docx", type: Documents::DocxBuilder::CONTENT_TYPE
      end

      csv = CSV.generate do |rows|
        rows << %w[code status target grade academic_year redeemed_by redeemed_at expires_on]
        batch.activation_codes.order(:id).each do |code|
          rows << [
            decrypt_code(code), code.status, redemption_target(code, batch), batch.grade&.name, batch.academic_year&.name,
            code.redeemed_by_student_profile&.user&.name, code.redeemed_at, batch.expires_on
          ]
        end
      end
      send_data csv, filename: "activation-codes-#{batch.id}.csv", type: "text/csv"
    end

    private

    def batch_params
      params.require(:activation_code_batch).permit(:name, :quantity, :expires_on)
    end

    def serialize_batch(batch, include_codes: false)
      payload = {
        id: batch.id, name: batch.name, lesson_id: batch.lesson_id, lesson: batch.lesson&.title,
        academic_year_id: batch.academic_year_id, academic_year: batch.academic_year&.name,
        grade_id: batch.grade_id, grade: batch.grade&.name, quantity: batch.quantity,
        generic: batch.generic?,
        expires_on: batch.expires_on, created_at: batch.created_at,
        counts: batch.activation_codes.group_by(&:status).transform_values(&:count)
      }
      return payload unless include_codes

      payload.merge(codes: batch.activation_codes.sort_by(&:id).map { |code| serialize_code(code) })
    end

    def serialize_code(code)
      {
        id: code.id, code: decrypt_code(code), status: code.status,
        redeemed_by: code.redeemed_by_student_profile&.user&.name, redeemed_at: code.redeemed_at,
        redeemed_lecture: code.lecture_access_grant&.lecture&.title
      }
    end

    def decrypt_code(code)
      ActivationCodes::Cipher.decrypt(code.code_ciphertext)
    end

    def redemption_target(code, batch)
      code.lecture_access_grant&.lecture&.title || batch.lesson&.title || "Any paid lecture"
    end
  end
end
