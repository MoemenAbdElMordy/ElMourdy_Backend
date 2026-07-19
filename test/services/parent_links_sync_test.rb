require "test_helper"

class ParentLinksSyncTest < ActiveSupport::TestCase
  test "links every student registered with the verified parent phone" do
    phone = unique_phone
    first_student = create_student(parent_phone: phone)
    second_student = create_student(parent_phone: phone)
    parent = create_parent(phone:)

    links = ParentLinks::Sync.call(parent_profile: parent)

    assert_equal 2, links.size
    assert_equal [ first_student.id, second_student.id ].sort, parent.student_profile_ids.sort
  end
end
