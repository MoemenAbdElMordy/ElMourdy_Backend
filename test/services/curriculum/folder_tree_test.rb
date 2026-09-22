require "test_helper"

class Curriculum::FolderTreeTest < ActiveSupport::TestCase
  setup do
    @year, @grade, @branch, @chapter, @lesson = create_curriculum
    @tree = Curriculum::FolderTree.new(@branch)
  end

  test "one explicit folder and a replay create exactly one record without legacy containers" do
    assert_no_difference ["Chapter.count", "Lesson.count", "Lecture.count"] do
      assert_difference "CurriculumNode.count", 1 do
        first = @tree.create_folder(title: "Review", request_key: "create-1")
        assert_equal first.id, @tree.create_folder(title: "Review", request_key: "create-1").id
      end
    end
    assert_raises(ApplicationService::Error) { @tree.create_folder(title: "Other", request_key: "create-1") }
  end

  test "invalid name leaves no partial records" do
    assert_no_difference "CurriculumNode.count" do
      assert_raises(ActiveRecord::RecordInvalid) { @tree.create_folder(title: " ", request_key: "empty") }
    end
  end

  test "cycles are rejected and moving to root keeps children" do
    first = @tree.create_folder(title: "First", request_key: "first")
    second = @tree.create_folder(title: "Second", parent_id: first.id, request_key: "second")
    assert_raises(ActiveRecord::RecordInvalid) { @tree.move(node_id: first.id, parent_id: second.id) }
    assert_nil first.reload.parent_id
    assert_equal first.id, second.reload.parent_id
    @tree.move(node_id: second.id)
    assert_nil second.reload.parent_id
  end

  test "reordering must include all siblings exactly once" do
    first = @tree.create_folder(title: "First", request_key: "first")
    second = @tree.create_folder(title: "Second", request_key: "second")
    assert_raises(ApplicationService::Error) { @tree.reorder(ordered_ids: [first.id, first.id]) }
    @tree.reorder(ordered_ids: [second.id, first.id])
    assert_equal [second.id, first.id], CurriculumNode.ordered.pluck(:id)
  end

  test "a dragged folder moves before a sibling atomically across levels" do
    parent = @tree.create_folder(title: "Chapter", request_key: "parent")
    first = @tree.create_folder(title: "First", parent_id: parent.id, request_key: "first")
    second = @tree.create_folder(title: "Second", parent_id: parent.id, request_key: "second")
    moved = @tree.create_folder(title: "Moved", request_key: "moved")

    @tree.move(node_id: moved.id, parent_id: parent.id, before_id: second.id)
    assert_equal [first.id, moved.id, second.id], CurriculumNode.where(parent_id: parent.id).ordered.pluck(:id)
    assert_equal parent.id, moved.reload.parent_id
    assert_raises(ApplicationService::Error) do
      @tree.move(node_id: first.id, parent_id: nil, before_id: second.id)
    end
    assert_equal parent.id, first.reload.parent_id
  end

  test "non empty folders cannot be removed" do
    first = @tree.create_folder(title: "First", request_key: "first")
    @tree.create_folder(title: "Second", parent_id: first.id, request_key: "second")
    assert_raises(ApplicationService::Error) { @tree.delete_empty_folder(node_id: first.id) }
    assert first.reload.persisted?
  end

  test "backfill is idempotent and moving a lecture preserves its legacy access anchor" do
    lecture = @lesson.lectures.create!(title: "Explanation", position: 1, status: :published)
    assert_no_difference ["Chapter.count", "Lesson.count", "Lecture.count"] do
      2.times { Curriculum::BackfillFolderTree.call(branch: @branch) }
    end
    assert_equal 3, CurriculumNode.count
    node = CurriculumNode.find_by!(lecture:)
    @tree.move(node_id: node.id)
    Curriculum::BackfillFolderTree.call(branch: @branch)
    assert_equal 3, CurriculumNode.count
    assert_nil node.reload.parent_id
    assert_equal @lesson.id, lecture.reload.lesson_id
  end

  test "cross subject parent is rejected" do
    other = Branch.create!(academic_year: @year, grade: @grade, title: "Rhetoric", position: 2, status: :published)
    foreign = Curriculum::FolderTree.new(other).create_folder(title: "Remote", request_key: "foreign")
    assert_raises(ActiveRecord::RecordNotFound) { @tree.create_folder(title: "Invalid", parent_id: foreign.id, request_key: "bad") }
  end
end
