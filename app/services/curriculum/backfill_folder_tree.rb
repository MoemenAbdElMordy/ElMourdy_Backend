module Curriculum
  # Explicitly invoked, never an implicit controller side effect. Keeps every
  # legacy record and ID. Running it again does not undo user moves/renames.
  class BackfillFolderTree < ApplicationService
    def self.call(branch:)
      branch.with_lock do
        branch.chapters.ordered.each do |chapter|
          next if Curriculum::LegacyAnchor.internal_chapter?(chapter)
          chapter_node = CurriculumNode.find_or_create_by!(legacy_chapter: chapter) do |node|
            node.assign_attributes(branch:, kind: "folder", title: chapter.title, position: chapter.position)
          end
          chapter.lessons.ordered.each do |lesson|
            lesson_node = CurriculumNode.find_or_create_by!(legacy_lesson: lesson) do |node|
              node.assign_attributes(branch:, parent: chapter_node, kind: "folder", title: lesson.title, position: lesson.position)
            end
            lesson.curriculum_lectures.each_with_index do |lecture, index|
              key = "legacy-lesson-#{lesson.id}-lecture-#{lecture.id}"
              CurriculumNode.find_or_create_by!(branch:, request_key: key) do |node|
                node.assign_attributes(parent: lesson_node, kind: "lecture", lecture:, title: lecture.title, position: index + 1)
              end
            end
          end
        end
      end
    end
  end
end
