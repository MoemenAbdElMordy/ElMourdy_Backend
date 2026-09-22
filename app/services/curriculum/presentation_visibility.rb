module Curriculum
  # A presentation node may be moved without rewriting its entitlement anchor.
  # Return nil for old content that has not been backfilled yet.
  class PresentationVisibility
    def self.visible?(lecture:, branch_ids:)
      nodes = CurriculumNode.where(lecture:, branch_id: branch_ids).includes(:branch, :legacy_chapter, :legacy_lesson).to_a
      return nil if nodes.empty?

      nodes.any? do |node|
        visible_record?(node.branch) && visible_ancestors?(node)
      end
    end

    def self.visible_ancestors?(node)
      cursor = node.parent
      while cursor
        return false if cursor.legacy_chapter && !visible_record?(cursor.legacy_chapter)
        return false if cursor.legacy_lesson && !visible_record?(cursor.legacy_lesson)
        cursor = cursor.parent
      end
      true
    end

    def self.visible_record?(record)
      record.published? && (record.try(:publish_at).nil? || record.publish_at <= Time.current)
    end
    private_class_method :visible_ancestors?, :visible_record?
  end
end
