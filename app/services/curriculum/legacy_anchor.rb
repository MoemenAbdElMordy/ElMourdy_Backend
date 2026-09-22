module Curriculum
  # Lectures still use a legacy lesson as the stable entitlement anchor. This
  # creates that backing record only when the first lecture is explicitly
  # saved in an otherwise empty subject. It never creates presentation nodes.
  class LegacyAnchor < ApplicationService
    CHAPTER_TITLE = "Internal content storage".freeze
    LESSON_TITLE = "Internal lecture storage".freeze

    def self.internal_chapter?(chapter)
      chapter.title == CHAPTER_TITLE && chapter.lessons.exists?(title: LESSON_TITLE)
    end

    def self.ensure_for!(branch)
      branch.with_lock do
        chapter = branch.chapters.find_by(title: CHAPTER_TITLE)
        return chapter.lessons.find_by!(title: LESSON_TITLE) if chapter&.lessons&.exists?(title: LESSON_TITLE)

        chapter ||= branch.chapters.create!(
          title: CHAPTER_TITLE,
          position: branch.chapters.maximum(:position).to_i + 1,
          status: "published"
        )
        chapter.lessons.create!(title: LESSON_TITLE, position: 1, status: "published", is_free: false)
      end
    end
  end
end
