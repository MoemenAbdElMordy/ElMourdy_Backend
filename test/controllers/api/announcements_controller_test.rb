require "test_helper"

class Api::AnnouncementsControllerTest < ActionDispatch::IntegrationTest
  test "teacher publishes an announcement to one grade" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    _year, grade = create_academic_setup

    post "/api/announcements", params: {
      announcement: { title: "Schedule update", body: "The next lecture starts at noon.", status: "published", grade_ids: [ grade.id ] }
    }, headers: auth(token), as: :json

    assert_response :created
    assert_equal [ grade.id ], response.parsed_body.dig("announcement", "grade_ids")
  end

  test "student sees global and matching grade announcements only" do
    year, grade = create_academic_setup
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: year, grade:, status: :active, enrolled_at: Time.current)
    matching = Announcement.create!(title: "Matching", body: "Visible", status: :published)
    matching.announcement_targets.create!(target_type: :grade, grade:)
    other_grade = Grade.where.not(id: grade.id).first || Grade.create!(name: "Other Grade", level: 2)
    hidden = Announcement.create!(title: "Other", body: "Hidden", status: :published)
    hidden.announcement_targets.create!(target_type: :grade, grade: other_grade)
    global = Announcement.create!(title: "Global", body: "Visible", status: :published)
    token = start_test_session(student.user).raw_token

    get "/api/announcements", headers: auth(token)

    assert_response :success
    assert_equal [ global.id, matching.id ].sort, response.parsed_body.fetch("announcements").pluck("id").sort
  end

  test "teacher targets an announcement to one student" do
    teacher = create_user(role: :teacher)
    token = Sessions::Start.call(user: teacher).raw_token
    student = create_student

    post "/api/announcements", params: {
      announcement: {
        title: "Private note", body: "Visible to one student", status: "published", user_ids: [ student.user_id ]
      }
    }, headers: auth(token), as: :json

    assert_response :created
    assert_equal [ student.user_id ], response.parsed_body.dig("announcement", "user_ids")
  end

  private

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
