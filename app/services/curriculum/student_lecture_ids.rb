module Curriculum
  class StudentLectureIds
    def self.for_branch(branch)
      legacy_ids = Lecture.published.where("lectures.publish_at IS NULL OR lectures.publish_at <= ?", Time.current)
        .joins(lesson: :chapter)
        .where(chapters: { branch_id: branch.id })
        .where(lessons: { id: Lesson.visible.select(:id) })
        .where(chapters: { id: Chapter.visible.select(:id) })
        .pluck(:id)

      placed_ids = CurriculumNode.where(branch:, kind: "lecture").includes(:lecture).filter_map do |node|
        lecture = node.lecture
        next unless lecture&.published? && (lecture.publish_at.nil? || lecture.publish_at <= Time.current)
        next unless Curriculum::PresentationVisibility.visible?(lecture:, branch_ids: [branch.id])

        lecture.id
      end

      (legacy_ids + placed_ids).uniq
    end
  end
end
