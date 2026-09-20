module Api
  class LecturesController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_content") }

    def create
      lecture = Lecture.transaction do
        attributes = lecture_params.to_h.symbolize_keys
        attributes[:lesson_id] ||= fallback_lesson.id
        attributes[:position] ||= Lecture.where(lesson_id: attributes[:lesson_id]).maximum(:position).to_i + 1
        record = Lecture.create!(attributes)
        sync_placements(record)
        attach_to_folder_tree(record)
        record
      end
      render json: { lecture: serialize(lecture) }, status: :created
    end

    def update
      Lecture.transaction do
        lecture.update!(lecture_params)
        sync_placements(lecture)
        lecture.curriculum_nodes.update_all(title: lecture.title, updated_at: Time.current) if lecture.saved_change_to_title?
      end
      render json: { lecture: serialize(lecture) }
    end

    def destroy
      Curriculum::DestroyLecture.call(lecture)
      head :no_content
    end

    def reorder
      Curriculum::Reorder.call(scope: Lecture.where(lesson_id: params.require(:lesson_id)), ordered_ids: params.require(:ordered_ids))
      head :no_content
    end

    private

    def lecture = @lecture ||= Lecture.find(params[:id])
    def lecture_params
      params.require(:lecture).permit(
        :lesson_id, :title, :description, :attachment_name, :attachment_url,
        :position, :status, :publish_at, :is_free, :duration_seconds
      )
    end
    def additional_lesson_ids
      return unless params.require(:lecture).key?(:additional_lesson_ids)

      Array(params.require(:lecture)[:additional_lesson_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    end
    def sync_placements(record)
      ids = additional_lesson_ids
      return if ids.nil?

      ids -= [ record.lesson_id ]
      lessons = Lesson.where(id: ids)
      raise ActiveRecord::RecordNotFound unless lessons.size == ids.size

      record.lecture_placements.where.not(lesson_id: ids).delete_all
      ids.each { |lesson_id| record.lecture_placements.find_or_create_by!(lesson_id:) }
    end
    def fallback_lesson
      branch_id = params.require(:lecture)[:branch_id]
      raise ActionController::ParameterMissing, :lesson_id if branch_id.blank?

      Curriculum::LegacyAnchor.ensure_for!(Branch.find(branch_id))
    end
    def attach_to_folder_tree(record)
      branch_id = params.require(:lecture)[:branch_id]
      return if branch_id.blank?

      branch = Branch.find(branch_id)
      parent_id = params.require(:lecture)[:parent_node_id].presence
      parent = parent_id && CurriculumNode.where(branch:, kind: "folder").find(parent_id)
      request_key = request.headers["Idempotency-Key"].presence || "lecture-#{record.id}"
      CurriculumNode.create!(
        branch:, parent:, lecture: record, kind: "lecture", title: record.title,
        request_key:, position: CurriculumNode.where(branch:, parent_id: parent&.id).maximum(:position).to_i + 1
      )
    end
    def serialize(record)
      record.as_json(
        only: %i[id lesson_id title description attachment_name attachment_url position status publish_at is_free duration_seconds]
      ).merge(
        has_thumbnail: record.thumbnail_key.present?,
        additional_lesson_ids: record.additional_lesson_ids
      )
    end
  end
end
