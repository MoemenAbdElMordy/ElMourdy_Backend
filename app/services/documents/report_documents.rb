module Documents
  class ReportDocuments
    class << self
      def students(users, title: "Student Report")
        document = DocxBuilder.new(title:)
        document.paragraph("Generated at: #{Time.current.iso8601}")
        rows = users.map do |user|
          profile = user.student_profile
          enrollment = profile.student_enrollments.active.max_by(&:enrolled_at)
          [
            user.name, user.phone_e164, user.status, enrollment&.grade&.name,
            enrollment&.academic_year&.name, profile.school, profile.center_name
          ]
        end
        document.table(headers: [ "Name", "Phone", "Status", "Grade", "Academic year", "School", "Center" ], rows:)
        document.render
      end

      def student(user)
        profile = user.student_profile
        enrollment = profile.student_enrollments.active.max_by(&:enrolled_at)
        document = DocxBuilder.new(title: "Student Profile Report")
        document.table(headers: [ "Field", "Value" ], rows: [
          [ "Name", user.name ], [ "Phone", user.phone_e164 ], [ "Email", user.email ], [ "Status", user.status ],
          [ "Grade", enrollment&.grade&.name ], [ "Academic year", enrollment&.academic_year&.name ],
          [ "School", profile.school ], [ "Center", profile.center_name ], [ "Governorate", profile.governorate ],
          [ "Parent phone", profile.parent_phone_e164 ],
          [ "Active devices", profile.device_registrations.active.count ],
          [ "Completed lectures", profile.lecture_watch_events.where.not(completed_at: nil).distinct.count(:lecture_id) ],
          [ "Highest score", profile.exam_attempts.submitted.maximum(:percent)&.to_f ]
        ])
        attempts = profile.exam_attempts.includes(:exam).submitted.order(submitted_at: :desc).limit(50).map do |attempt|
          [ attempt.exam.title, attempt.attempt_number, attempt.percent, attempt.result_status, attempt.submitted_at ]
        end
        document.heading("Recent assessment results", level: 2)
        document.table(headers: [ "Assessment", "Attempt", "Score", "Result", "Submitted at" ], rows: attempts)
        document.render
      end

      def management(overview:, students:, filters:)
        document = DocxBuilder.new(title: "Platform Management Report")
        filter_text = filters.compact_blank.map { |key, value| "#{key}=#{value}" }.join(", ").presence || "All data"
        document.paragraph("Filters: #{filter_text}")
        document.table(headers: [ "Metric", "Value" ], rows: overview.map { |key, value| [ key.to_s.humanize, value ] })
        document.heading("Students", level: 2)
        rows = students.map do |student|
          [ student[:name], student[:grade], student[:academic_year], student[:average_score]&.round(2),
            student[:attempts_count], student[:completed_lectures], student[:center_name], student[:last_active_at] ]
        end
        document.table(headers: [
          "Name", "Grade", "Academic year", "Average score", "Attempts", "Completed lectures", "Center", "Last active"
        ], rows:)
        document.render
      end

      def activation_codes(batch, codes)
        document = DocxBuilder.new(title: "Activation Code Batch")
        document.table(headers: [ "Field", "Value" ], rows: [
          [ "Batch", batch.name ], [ "Scope", batch.generic? ? "Any paid lecture" : batch.lesson.title ],
          [ "Grade", batch.grade&.name || "Any eligible grade" ],
          [ "Academic year", batch.academic_year&.name || "Student's active year" ],
          [ "Expires on", batch.expires_on ], [ "Quantity", batch.quantity ]
        ])
        rows = codes.map { |code| [ code[:code], code[:status], code[:redeemed_by], code[:redeemed_at], batch.expires_on ] }
        document.heading("Codes", level: 2)
        document.table(headers: [ "Code", "Status", "Redeemed by", "Redeemed at", "Expires on" ], rows:)
        document.render
      end
    end
  end
end
