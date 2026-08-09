module RecordFactory
  def unique_phone
    "+201#{SecureRandom.random_number(100_000_000).to_s.rjust(8, '0')}"
  end

  def create_user(role: :student, phone: unique_phone)
    User.create!(
      role:,
      name: "Test User",
      phone_e164: phone,
      password: "ValidPassword123!",
      password_confirmation: "ValidPassword123!",
      status: :active,
      phone_verified_at: Time.current
    )
  end

  def create_student(parent_phone: unique_phone)
    user = create_user(role: :student)
    StudentProfile.create!(
      user:,
      birth_date: Date.new(2008, 1, 1),
      parent_phone_e164: parent_phone
    )
  end

  def create_parent(phone: unique_phone)
    user = create_user(role: :parent, phone:)
    ParentProfile.create!(user:, verified_parent_phone_e164: phone)
  end

  def start_test_session(user)
    device = if user.student?
      user.student_profile.device_registrations.create!(
        device_fingerprint_digest: Security::DigestValue.call(SecureRandom.hex(12)),
        status: :active
      )
    end
    Sessions::Start.call(user:, device_registration: device)
  end

  def create_curriculum
    year = AcademicYear.create!(
      name: "#{SecureRandom.hex(4)}/2027",
      starts_on: Date.new(2026, 9, 1),
      ends_on: Date.new(2027, 8, 31),
      status: :active
    )
    grade = Grade.create!(name: "Grade #{SecureRandom.hex(3)}", level: available_grade_level)
    branch = Branch.create!(academic_year: year, grade:, title: "Grammar", position: 1, status: :published)
    chapter = Chapter.create!(branch:, title: "Foundations", position: 1, status: :published)
    lesson = Lesson.create!(chapter:, title: "Introduction", position: 1, status: :published)
    [ year, grade, branch, chapter, lesson ]
  end

  def create_academic_setup
    grade = Grade.find_or_create_by!(level: 1) do |record|
      record.name = "First Secondary"
      record.active = true
    end
    year = AcademicYear.create!(
      name: "#{SecureRandom.hex(4)}/2027",
      starts_on: Date.new(2026, 9, 1),
      ends_on: Date.new(2027, 8, 31),
      status: :active
    )
    [ year, grade ]
  end

  def create_exam
    year, grade, _branch, _chapter, lesson = create_curriculum
    exam = Exam.create!(
      title: "Lesson Exam",
      scope_type: :lesson,
      lesson:,
      academic_year: year,
      grade:,
      duration_minutes: 30,
      max_attempts: 3,
      pass_percent: 50,
      risk_from_percent: 50,
      risk_to_percent: 60,
      status: :published
    )
    2.times do |index|
      question = exam.exam_questions.create!(body: "Question #{index + 1}", points: 1, position: index + 1)
      question.exam_choices.create!(body: "Correct", is_correct: true, position: 1)
      question.exam_choices.create!(body: "Incorrect", is_correct: false, position: 2)
    end
    exam
  end

  private

  def available_grade_level
    (1..3).detect { |level| !Grade.exists?(level:) } || raise("No grade level available in this test")
  end
end
