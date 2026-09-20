require "test_helper"

class Curriculum::FolderTreeTest < ActiveSupport::TestCase
  setup do
    @year, @grade, @branch, @chapter, @lesson = create_curriculum
    @tree = Curriculum::FolderTree.new(@branch)
  end

  test "one explicit folder and a replay create exactly one record without legacy containers" do
    assert_no_difference ["Chapter.count", "Lesson.count", "Lecture.count"] do
      assert_difference "CurriculumNode.count", 1 do
        first = @tree.create_folder(title: "مراجعة", request_key: "create-1")
        assert_equal first.id, @tree.create_folder(title: "مراجعة", request_key: "create-1").id
      end
    end
    assert_raises(ApplicationService::Error) { @tree.create_folder(title: "آخر", request_key: "create-1") }
  end

  test "invalid name leaves no partial records" do
    assert_no_difference "CurriculumNode.count" do
      assert_raises(ActiveRecord::RecordInvalid) { @tree.create_folder(title: " ", request_key: "empty") }
    end
  end

  test "cycles are rejected and moving to root keeps children" do
    first = @tree.create_folder(title: "أول", request_key: "first")
    second = @tree.create_folder(title: "ثان", parent_id: first.id, request_key: "second")
    assert_raises(ActiveRecord::RecordInvalid) { @tree.move(node_id: first.id, parent_id: second.id) }
    assert_nil first.reload.parent_id
    assert_equal first.id, second.reload.parent_id
    @tree.move(node_id: second.id)
    assert_nil second.reload.parent_id
  end

  test "reordering must include all siblings exactly once" do
    first = @tree.create_folder(title: "أول", request_key: "first")
    second = @tree.create_folder(title: "ثان", request_key: "second")
    assert_raises(ApplicationService::Error) { @tree.reorder(ordered_ids: [first.id, first.id]) }
    @tree.reorder(ordered_ids: [second.id, first.id])
    assert_equal [second.id, first.id], CurriculumNode.ordered.pluck(:id)
  end

  test "non empty folders cannot be removed" do
    first = @tree.create_folder(title: "أول", request_key: "first")
    @tree.create_folder(title: "ثان", parent_id: first.id, request_key: "second")
    assert_raises(ApplicationService::Error) { @tree.delete_empty_folder(node_id: first.id) }
    assert first.reload.persisted?
  end

  test "backfill is idempotent and moving a lecture preserves its legacy access anchor" do
    lecture = @lesson.lectures.create!(title: "شرح", position: 1, status: :published)
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
    other = Branch.create!(academic_year: @year, grade: @grade, title: "بلاغة", position: 2, status: :published)
    foreign = Curriculum::FolderTree.new(other).create_folder(title: "بعيد", request_key: "foreign")
    assert_raises(ActiveRecord::RecordNotFound) { @tree.create_folder(title: "غير صحيح", parent_id: foreign.id, request_key: "bad") }
  end
end
