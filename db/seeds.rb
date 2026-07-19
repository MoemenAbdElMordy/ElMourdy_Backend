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

teacher_password = if Rails.env.production?
  ENV.fetch("SEED_TEACHER_PASSWORD")
else
  ENV.fetch("SEED_TEACHER_PASSWORD", "ChangeMe123!ForDevelopment")
end

User.find_or_create_by!(phone_e164: "+201000000000") do |user|
  user.name = "Platform Teacher"
  user.phone_display = "01000000000"
  user.password = teacher_password
  user.password_confirmation = teacher_password
  user.role = :teacher
  user.status = :active
  user.phone_verified_at = Time.current
end
