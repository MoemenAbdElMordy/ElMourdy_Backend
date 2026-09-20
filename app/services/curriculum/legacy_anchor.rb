module Curriculum
  # Lectures still use a legacy lesson as the stable entitlement anchor. This
  # creates that backing record only when the first lecture is explicitly
  # saved in an otherwise empty subject. It never creates presentation nodes.
  class LegacyAnchor < ApplicationService
    def self.ensure_for!(branch)
      branch.with_lock do
        lesson = Lesson.joins(:chapter)
          .where(chapters: { branch_id: branch.id })
          .order("chapters.position ASC", "lessons.position ASC", "lessons.id ASC")
          .first
        return lesson if lesson

        chapter = branch.chapters.create!(
          title: "سجل المحتوى الداخلي",
          position: branch.chapters.maximum(:position).to_i + 1,
          status: "published"
        )
        chapter.lessons.create!(
          title: "سجل المحاضرات الداخلي",
          position: 1,
          status: "published",
          is_free: false
        )
      end
    end
  end
end
