module DemoData
  PREFIX = "[DEMO]".freeze
  USER_EMAIL_PATTERN = "demo.%@mourdy.local".freeze
  DEMO_PASSWORD = "DemoStudent2026!".freeze
  FIXED_TEACHER_PHONE = "+201200000003".freeze
  FIXED_STUDENT_PHONE = "+201000000001".freeze
  FIXED_PARENT_PHONE = "+201100000002".freeze

  module_function

  def seed!
    purge!

    teacher = User.teacher.find_by!(phone_e164: FIXED_TEACHER_PHONE)
    main_student = User.student.find_by!(phone_e164: FIXED_STUDENT_PHONE).student_profile
    parent = User.parent.find_by!(phone_e164: FIXED_PARENT_PHONE).parent_profile
    year = AcademicYear.active.first || create_demo_year!
    grades = ensure_grades!

    enroll!(main_student, year, grades.fetch(1))
    link_parent!(parent, main_student)
    main_student.update!(governorate: "Giza", school: "Demo Secondary School")

    demo_students = create_demo_students!(year:, grades:, parent:)
    branches, lessons, lectures = create_curriculum!(year:, grade: grades.fetch(1))
    exams = create_exams!(year:, grade: grades.fetch(1), lessons:, teacher:)

    grant_access!(main_student, year, lessons)
    seed_watch_history!(main_student, lectures, completed_count: 5, view_offset: 0)
    create_attempt!(main_student, exams.first, percent: 88, days_ago: 3)
    create_attempt!(main_student, exams.last, percent: 54, days_ago: 1)

    demo_scores = [ 96, 82, 71, 52, 31 ]
    demo_students.each_with_index do |student, index|
      seed_watch_history!(student, lectures, completed_count: [ 7 - index, 2 ].max, view_offset: index + 1)
      create_attempt!(student, exams.first, percent: demo_scores.fetch(index), days_ago: index + 1)
      create_activity_session!(student, days_ago: index + 1)
    end

    create_announcements!(teacher:, grade: grades.fetch(1), main_student:)
    create_support_requests!(demo_students, exams.first)
    create_audit_logs!(teacher:, students: demo_students, branches:, exams:)

    puts({
      demo_students: demo_students.length,
      demo_branches: branches.length,
      demo_lessons: lessons.length,
      demo_lectures: lectures.length,
      demo_exams: exams.length,
      demo_attempts: ExamAttempt.where(exam_id: exams.map(&:id)).count
    }.to_json)
  end

  def purge!
    demo_users = User.where("email LIKE ?", USER_EMAIL_PATTERN)
    demo_user_ids = demo_users.pluck(:id)
    demo_student_ids = StudentProfile.where(user_id: demo_user_ids).pluck(:id)
    demo_parent_ids = ParentProfile.where(user_id: demo_user_ids).pluck(:id)
    demo_assistant_ids = AssistantProfile.where(user_id: demo_user_ids).pluck(:id)

    demo_branches = Branch.where("title LIKE ?", "#{PREFIX}%")
    demo_branch_ids = demo_branches.pluck(:id)
    demo_chapter_ids = Chapter.where(branch_id: demo_branch_ids).pluck(:id)
    demo_lesson_ids = Lesson.where(chapter_id: demo_chapter_ids).pluck(:id)
    demo_lecture_ids = Lecture.where(lesson_id: demo_lesson_ids).pluck(:id)
    demo_exam_ids = Exam.where("title LIKE ?", "#{PREFIX}%").pluck(:id)
    demo_question_ids = ExamQuestion.where(exam_id: demo_exam_ids).pluck(:id)
    demo_attempt_ids = ExamAttempt.where(exam_id: demo_exam_ids).pluck(:id)
    demo_announcement_ids = Announcement.where("title LIKE ?", "#{PREFIX}%").pluck(:id)
    demo_support_ids = SupportRequest.where("reason LIKE ?", "#{PREFIX}%").pluck(:id)
    demo_video_asset_ids = VideoAsset.where(lecture_id: demo_lecture_ids).pluck(:id)

    target_groups = {
      "User" => demo_user_ids,
      "Branch" => demo_branch_ids,
      "Lesson" => demo_lesson_ids,
      "Lecture" => demo_lecture_ids,
      "Exam" => demo_exam_ids,
      "Announcement" => demo_announcement_ids,
      "SupportRequest" => demo_support_ids
    }
    target_groups.each do |target_type, ids|
      AuditLog.where(target_type:, target_id: ids).delete_all if ids.any?
    end
    AuditLog.where(actor_user_id: demo_user_ids).delete_all if demo_user_ids.any?

    SupportRequestAction.where(support_request_id: demo_support_ids).delete_all
    SupportRequest.where(id: demo_support_ids).delete_all
    AnnouncementTarget.where(announcement_id: demo_announcement_ids).delete_all
    Announcement.where(id: demo_announcement_ids).delete_all
    ExamAnswer.where(exam_attempt_id: demo_attempt_ids).or(ExamAnswer.where(exam_question_id: demo_question_ids)).delete_all
    ExamAttempt.where(id: demo_attempt_ids).delete_all
    ExamChoice.where(exam_question_id: demo_question_ids).delete_all
    ExamQuestion.where(id: demo_question_ids).delete_all
    Exam.where(id: demo_exam_ids).delete_all
    LectureWatchEvent.where(lecture_id: demo_lecture_ids).delete_all
    LessonAccessGrant.where(lesson_id: demo_lesson_ids).delete_all
    VideoVariant.where(video_asset_id: demo_video_asset_ids).delete_all
    VideoAsset.where(id: demo_video_asset_ids).delete_all
    Lecture.where(id: demo_lecture_ids).delete_all
    Lesson.where(id: demo_lesson_ids).delete_all
    Chapter.where(id: demo_chapter_ids).delete_all
    Branch.where(id: demo_branch_ids).delete_all

    if demo_user_ids.any?
      UserSession.where(user_id: demo_user_ids).delete_all
      DeviceRegistration.where(student_profile_id: demo_student_ids).delete_all
      StudentParentLink.where(student_profile_id: demo_student_ids).or(
        StudentParentLink.where(parent_profile_id: demo_parent_ids)
      ).delete_all
      StudentEnrollment.where(student_profile_id: demo_student_ids).delete_all
      AssistantPermission.where(assistant_profile_id: demo_assistant_ids).delete_all
      AssistantProfile.where(id: demo_assistant_ids).delete_all
      ParentProfile.where(id: demo_parent_ids).delete_all
      StudentProfile.where(id: demo_student_ids).delete_all
      User.where(id: demo_user_ids).delete_all
    end

    AcademicYear.where(name: "#{PREFIX} Academic Year").where.missing(:branches, :student_enrollments).delete_all
    puts({ purged: true }.to_json)
  end

  def create_demo_year!
    AcademicYear.create!(
      name: "#{PREFIX} Academic Year",
      starts_on: Date.current.beginning_of_year,
      ends_on: Date.current.end_of_year,
      status: :active
    )
  end

  def ensure_grades!
    {
      1 => "First Secondary",
      2 => "Second Secondary",
      3 => "Third Secondary"
    }.to_h do |level, name|
      grade = Grade.find_or_create_by!(level:) { |record| record.name = name }
      grade.update!(active: true)
      [ level, grade ]
    end
  end

  def create_demo_students!(year:, grades:, parent:)
    five_students = [
      [ "Demo Student Alpha", "+201090000010", 1 ],
      [ "Demo Student Beta", "+201090000011", 1 ],
      [ "Demo Student Gamma", "+201090000012", 1 ],
      [ "Demo Student Delta", "+201090000013", 2 ],
      [ "Demo Student Epsilon", "+201090000014", 2 ]
    ]

    five_students.map.with_index do |(name, phone, level), index|
      user = User.create!(
        name:, phone_e164: phone, email: "demo.student.#{index + 1}@mourdy.local",
        password: DEMO_PASSWORD, password_confirmation: DEMO_PASSWORD,
        role: :student, status: :active, phone_verified_at: Time.current
      )
      student = StudentProfile.create!(
        user:, birth_date: Date.new(2008, index + 1, index + 2),
        parent_phone_e164: parent.user.phone_e164,
        governorate: index.even? ? "Giza" : "Cairo",
        school: "#{PREFIX} Secondary School #{index + 1}"
      )
      enroll!(student, year, grades.fetch(level))
      link_parent!(parent, student)
      student
    end
  end

  def enroll!(student, year, grade)
    enrollment = student.student_enrollments.find_or_initialize_by(academic_year: year)
    enrollment.update!(grade:, status: :active, enrolled_at: Time.current)
  end

  def link_parent!(parent, student)
    link = StudentParentLink.find_or_initialize_by(parent_profile: parent, student_profile: student)
    link.update!(relation: :guardian, status: :active, linked_at: Time.current)
  end

  def create_curriculum!(year:, grade:)
    next_position = Branch.where(academic_year: year, grade:).maximum(:position).to_i + 1
    branch_titles = [ "#{PREFIX} Grammar Foundations", "#{PREFIX} Reading Skills" ]
    lessons = []
    lectures = []
    branches = branch_titles.map.with_index do |title, branch_index|
      branch = Branch.create!(
        academic_year: year, grade:, title:, position: next_position + branch_index, status: :published
      )
      2.times do |chapter_index|
        chapter = branch.chapters.create!(
          title: "#{PREFIX} Unit #{branch_index + 1}.#{chapter_index + 1}",
          position: chapter_index + 1, status: :published
        )
        2.times do |lesson_index|
          lesson = chapter.lessons.create!(
            title: "#{PREFIX} Lesson #{branch_index + 1}.#{chapter_index + 1}.#{lesson_index + 1}",
            position: lesson_index + 1, status: :published,
            is_free: lesson_index.zero?, publish_at: 10.days.ago
          )
          lessons << lesson
          2.times do |lecture_index|
            lectures << lesson.lectures.create!(
              title: "#{PREFIX} Lecture #{branch_index + 1}.#{chapter_index + 1}.#{lesson_index + 1}.#{lecture_index + 1}",
              position: lecture_index + 1, status: :published,
              is_free: lesson.is_free, duration_seconds: 5_400, publish_at: 7.days.ago
            )
          end
          lesson.lectures.create!(
            title: "#{PREFIX} Upcoming Lecture #{branch_index + 1}.#{chapter_index + 1}.#{lesson_index + 1}",
            position: 3, status: :draft, duration_seconds: 5_400
          )
        end
      end
      branch
    end
    [ branches, lessons, lectures ]
  end

  def create_exams!(year:, grade:, lessons:, teacher:)
    exam_specs = [
      [ "#{PREFIX} Grammar Progress Exam", :lesson, lessons.first ],
      [ "#{PREFIX} Comprehensive Review", :comprehensive, nil ]
    ]
    exam_specs.map do |title, scope_type, lesson|
      exam = Exam.create!(
        title:, scope_type:, lesson:, academic_year: year, grade:,
        duration_minutes: 30, max_attempts: 3, pass_percent: 60,
        risk_from_percent: 40, risk_to_percent: 59,
        status: :draft, created_by_user: teacher
      )
      4.times do |index|
        question = exam.exam_questions.create!(
          body: "#{PREFIX} Question #{index + 1} for #{title}",
          explanation: "#{PREFIX} Explanation for question #{index + 1}",
          points: 25, position: index + 1
        )
        question.exam_choices.create!(body: "Correct answer", is_correct: true, position: 1)
        question.exam_choices.create!(body: "Incorrect answer", is_correct: false, position: 2)
      end
      exam.update!(status: :published)
      exam
    end
  end

  def create_attempt!(student, exam, percent:, days_ago:)
    submitted_at = days_ago.days.ago
    result_status = percent >= exam.pass_percent ? :passed : percent >= exam.risk_from_percent ? :risk : :failed
    attempt = ExamAttempt.create!(
      exam:, student_profile: student, attempt_number: 1,
      started_at: submitted_at - 20.minutes, submitted_at:,
      score_points: percent, max_points: 100, percent:,
      result_status:, status: :submitted,
      question_order: exam.exam_questions.order(:position).pluck(:id)
    )
    exam.exam_questions.includes(:exam_choices).order(:position).each_with_index do |question, index|
      correct = index < (percent / 25.0).floor
      selected = question.exam_choices.find { |choice| choice.is_correct? == correct }
      attempt.exam_answers.create!(
        exam_question: question, selected_choice: selected,
        is_correct: correct, points_awarded: correct ? question.points : 0
      )
    end
    attempt
  end

  def grant_access!(student, year, lessons)
    lessons.each do |lesson|
      grant = LessonAccessGrant.find_or_initialize_by(student_profile: student, lesson:, academic_year: year)
      grant.update!(source: :manual, status: :active, expires_on: 120.days.from_now.to_date)
    end
  end

  def seed_watch_history!(student, lectures, completed_count:, view_offset:)
    lectures.each_with_index do |lecture, index|
      completed = index < completed_count
      LectureWatchEvent.create!(
        student_profile: student, lecture:,
        started_at: (index + view_offset + 1).days.ago,
        completed_at: completed ? (index + view_offset).days.ago : nil,
        last_position_seconds: completed ? lecture.duration_seconds.to_i : 1_200
      )
      next unless index < 3

      view_offset.times do |repeat|
        LectureWatchEvent.create!(
          student_profile: student, lecture:,
          started_at: (repeat + 15).days.ago,
          completed_at: (repeat + 15).days.ago,
          last_position_seconds: lecture.duration_seconds.to_i
        )
      end
    end
  end

  def create_announcements!(teacher:, grade:, main_student:)
    global = Announcement.create!(
      title: "#{PREFIX} Weekly Study Plan",
      body: "Review the completed lectures and prepare for the next comprehensive exam.",
      status: :published, publish_at: 1.day.ago, created_by_user: teacher
    )
    targeted = Announcement.create!(
      title: "#{PREFIX} Personal Progress Update",
      body: "Your recent progress is strong. Continue with the remaining lectures.",
      status: :published, publish_at: 2.hours.ago, created_by_user: teacher
    )
    global.announcement_targets.create!(target_type: :grade, grade:)
    targeted.announcement_targets.create!(target_type: :user, user: main_student.user)
  end

  def create_support_requests!(students, exam)
    device = students.first.device_registrations.create!(
      device_fingerprint_digest: Security::DigestValue.call("demo-device-1"),
      device_name: "#{PREFIX} Old Laptop", browser: "Chrome", os: "Windows",
      status: :active, last_seen_at: 45.days.ago
    )
    students.first.user.support_requests.create!(
      student_profile: students.first, request_type: :device_removal,
      reason: "#{PREFIX} Remove an old device", payload: { device_registration_id: device.id }
    )
    students.second.user.support_requests.create!(
      student_profile: students.second, request_type: :extra_exam_attempt,
      reason: "#{PREFIX} Request one additional attempt", payload: { exam_id: exam.id }
    )
  end

  def create_activity_session!(student, days_ago:)
    last_seen_at = days_ago.days.ago
    device = student.device_registrations.create!(
      device_fingerprint_digest: Security::DigestValue.call("demo-active-device-#{student.id}"),
      device_name: "#{PREFIX} Student Device", browser: "Chrome", os: "Windows",
      status: :active, last_seen_at:
    )
    student.user.user_sessions.create!(
      device_registration: device,
      session_token_digest: Security::DigestValue.call("demo-session-#{student.user.id}"),
      started_at: last_seen_at - 2.hours, last_seen_at:, ended_at: last_seen_at,
      status: :ended
    )
  end

  def create_audit_logs!(teacher:, students:, branches:, exams:)
    targets = [ students.first.user, students.second.user, branches.first, branches.last, exams.first ]
    actions = %w[
      demo.student_reviewed demo.student_activated demo.content_published
      demo.curriculum_updated demo.exam_published
    ]
    targets.zip(actions).each_with_index do |(target, action), index|
      AuditLog.create!(
        actor_user: teacher, action:, target:,
        metadata: { demo: true }, ip_address: "127.0.0.1",
        created_at: (index + 1).hours.ago
      )
    end
  end
end

namespace :demo do
  desc "Create development-only dashboard data"
  task seed: :environment do
    abort "Demo data cannot be seeded in production" if Rails.env.production?

    DemoData.seed!
  end

  desc "Remove development-only dashboard data"
  task purge: :environment do
    abort "Demo data cannot be purged in production" if Rails.env.production?

    DemoData.purge!
  end
end
