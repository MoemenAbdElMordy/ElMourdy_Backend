grades = [
  { level: 1, name: "First Secondary" },
  { level: 2, name: "Second Secondary" },
  { level: 3, name: "Third Secondary" }
]

grades.each do |attributes|
  Grade.find_or_create_by!(level: attributes.fetch(:level)) do |grade|
    grade.name = attributes.fetch(:name)
    grade.active = true
  end
end

AcademicYear.find_or_create_by!(name: "2026/2027") do |year|
  year.starts_on = Date.new(2026, 9, 1)
  year.ends_on = Date.new(2027, 8, 31)
  year.status = :active
end

teacher_password = ENV.fetch("SEED_TEACHER_PASSWORD")
teacher_phone = ENV.fetch("SEED_TEACHER_PHONE")
teacher = User.teacher.order(:id).first_or_initialize
teacher.assign_attributes(
  name: "Platform Teacher",
  phone_e164: PhoneNumbers::Normalize.call(teacher_phone),
  phone_display: teacher_phone,
  password: teacher_password,
  password_confirmation: teacher_password,
  role: :teacher,
  status: :active,
  phone_verified_at: Time.current
)
teacher.save!
