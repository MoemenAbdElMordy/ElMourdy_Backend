require "test_helper"
require "tempfile"
require "zip"

class Api::DocumentWorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = create_user(role: :teacher)
    @token = Sessions::Start.call(user: @teacher).raw_token
    @year, @grade, _branch, _chapter, @lesson = create_curriculum
  end

  test "teacher imports multiple choice questions from a DOCX document" do
    document = Documents::DocxBuilder.new(title: "Import Fixture")
    document.paragraph("1. Which option is correct?")
    document.paragraph("A) First choice")
    document.paragraph("B) Second choice")
    document.paragraph("C) Third choice")
    document.paragraph("Answer: B")
    upload = uploaded_docx(document.render)

    post api_exam_imports_url, params: { assessment_type: "exam", file: upload }, headers: authorization_header(@token)

    assert_response :success
    question = response.parsed_body.dig("import", "questions", 0)
    assert_equal "Which option is correct?", question.fetch("body")
    assert_equal 3, question.fetch("choices").size
    assert_equal 1, question.fetch("correct_choice_index")
  ensure
    upload&.tempfile&.close!
  end

  test "teacher exports student and management reports as valid DOCX documents" do
    student = create_student
    StudentEnrollment.create!(student_profile: student, academic_year: @year, grade: @grade, status: :active, enrolled_at: Time.current)

    get export_api_students_url, headers: authorization_header(@token)
    assert_docx_response("Student Report")

    get export_one_api_student_url(student.user), headers: authorization_header(@token)
    assert_docx_response("Student Profile Report")

    get export_api_management_report_url, headers: authorization_header(@token)
    assert_docx_response("Platform Management Report")
  end

  private

  def authorization_header(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def uploaded_docx(content)
    file = Tempfile.new([ "exam-import", ".docx" ])
    file.binmode
    file.write(content)
    file.flush
    file.close
    Rack::Test::UploadedFile.new(file.path, Documents::DocxBuilder::CONTENT_TYPE, true, original_filename: "exam.docx")
  end

  def assert_docx_response(expected_text)
    assert_response :success
    assert_equal Documents::DocxBuilder::CONTENT_TYPE, response.media_type
    Zip::File.open_buffer(response.body) do |archive|
      xml = archive.find_entry("word/document.xml").get_input_stream.read
      assert_includes xml, expected_text
    end
  end
end
