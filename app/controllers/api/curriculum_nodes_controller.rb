module Api
  class CurriculumNodesController < ApplicationController
    before_action :authenticate_user!
    before_action -> { require_teacher_or_assistant_permission!("manage_content") }

    def create
      node = tree.create_folder(
        title: node_params.require(:title),
        parent_id: node_params[:parent_id],
        request_key: request.headers["Idempotency-Key"].presence || node_params[:request_key]
      )
      audit!(action: "curriculum.folder.create", target: node, metadata: { branch_id: branch.id, parent_id: node.parent_id })
      render json: { node: serialize(node) }, status: :created
    end

    def update
      node = tree.rename(node_id: params[:id], title: node_params.require(:title))
      audit!(action: "curriculum.folder.rename", target: node, metadata: { branch_id: branch.id })
      render json: { node: serialize(node) }
    end

    def move
      node = tree.move(node_id: params[:id], parent_id: node_params[:parent_id], before_id: node_params[:before_id])
      audit!(action: "curriculum.node.move", target: node, metadata: { branch_id: branch.id, parent_id: node.parent_id })
      render json: { node: serialize(node) }
    end

    def reorder
      tree.reorder(parent_id: node_params[:parent_id], ordered_ids: params.require(:ordered_ids))
      head :no_content
    end

    def destroy
      node = CurriculumNode.where(branch:).find(params[:id])
      tree.delete_empty_folder(node_id: node.id)
      audit!(action: "curriculum.folder.destroy", target: branch, metadata: { branch_id: branch.id, node_id: node.id })
      head :no_content
    end

    def backfill
      Curriculum::BackfillFolderTree.call(branch:)
      audit!(action: "curriculum.folder.backfill", target: branch, metadata: { branch_id: branch.id })
      render json: { nodes: serialize_tree }
    end

    private

    def branch = @branch ||= Branch.find(params.require(:branch_id))
    def tree = @tree ||= Curriculum::FolderTree.new(branch)
    def node_params = params.fetch(:node, {}).permit(:title, :parent_id, :before_id, :request_key)

    def serialize_tree(parent_id = nil)
      CurriculumNode.where(branch:, parent_id:).ordered.map do |node|
        serialize(node).merge(children: node.kind == "folder" ? serialize_tree(node.id) : [])
      end
    end

    def serialize(node)
      {
        id: node.id, branch_id: node.branch_id, parent_id: node.parent_id,
        kind: node.kind, title: node.kind == "lecture" ? node.lecture.title : node.title,
        position: node.position, lecture_id: node.lecture_id,
        legacy_chapter_id: node.legacy_chapter_id, legacy_lesson_id: node.legacy_lesson_id
      }
    end
  end
end
