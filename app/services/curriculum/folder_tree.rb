module Curriculum
  # Lock the subject for every mutation, including backfill. A stable request key
  # makes retries safe even after a response is lost. No network/storage writes.
  class FolderTree < ApplicationService
    def initialize(branch)
      @branch = branch
    end

    def create_folder(title:, parent_id: nil, request_key:)
      raise Error, "A request key is required" if request_key.blank? || request_key.length > 100

      @branch.with_lock do
        existing = nodes.find_by(request_key:)
        if existing
          unless existing.kind == "folder" && existing.title == title.to_s.strip && existing.parent_id == normalize_parent(parent_id)
            raise Error, "This request key was already used for another folder"
          end
          return existing
        end
        parent = folder(parent_id)
        nodes.create!(kind: "folder", title: title.to_s.strip, parent:, request_key:,
          position: siblings(parent&.id).maximum(:position).to_i + 1)
      end
    end

    def rename(node_id:, title:)
      @branch.with_lock do
        node = nodes.find(node_id)
        raise Error, "Use the lecture editor to rename a lecture" unless node.kind == "folder"
        node.update!(title: title.to_s.strip)
        node
      end
    end

    def move(node_id:, parent_id: nil)
      @branch.with_lock do
        node = nodes.find(node_id)
        parent = folder(parent_id)
        return node if node.parent_id == parent&.id

        old_parent = node.parent_id
        node.update!(parent:, position: siblings(parent&.id).maximum(:position).to_i + 1)
        compact(old_parent)
        node
      end
    end

    def reorder(parent_id: nil, ordered_ids:)
      @branch.with_lock do
        parent = folder(parent_id)
        records = siblings(parent&.id).index_by(&:id)
        ids = Array(ordered_ids).map { |id| Integer(id, exception: false) }
        unless ids.all? && ids.uniq.size == ids.size && ids.sort == records.keys.sort
          raise Error, "The ordering list must contain every item exactly once"
        end
        ids.each_with_index { |id, index| records.fetch(id).update!(position: index + 1) }
      end
    end

    def delete_empty_folder(node_id:)
      @branch.with_lock do
        node = nodes.find(node_id)
        raise Error, "Only empty folders can be deleted here" unless node.kind == "folder" && !node.children.exists?
        parent_id = node.parent_id
        node.destroy!
        compact(parent_id)
      end
    end

    private

    def nodes = CurriculumNode.where(branch: @branch)
    def siblings(parent_id) = nodes.where(parent_id:).ordered
    def normalize_parent(id) = id.blank? ? nil : Integer(id)

    def folder(id)
      return if id.blank?
      nodes.where(kind: "folder").find(id)
    end

    def compact(parent_id)
      siblings(parent_id).each_with_index { |node, index| node.update!(position: index + 1) }
    end
  end
end
