require "pdf-reader"
require_relative "exam_docx_parser"

module Documents
  class ExamPdfParser < ExamDocxParser
    MAX_PDF_SIZE = 25.megabytes

    def call
      validate_pdf!
      reader = build_reader
      page_texts = reader.pages.map { |page| page.text.to_s }
      extracted_text = page_texts.sum(&:length)
      raise ApplicationService::Error, "The PDF does not contain selectable text and requires OCR" if extracted_text.zero?

      reverse_lines = reversed_text_score(page_texts) > normal_text_score(page_texts)
      page_texts.each do |text|
        text.lines.each do |line|
          normalized_line = reverse_lines ? line.strip.reverse : line.strip
          parse_paragraph(normalized_line, @questions ||= [])
        end
      end

      questions = @questions || []
      finalize_current(questions)
      raise ApplicationService::Error, "No multiple-choice questions could be recognized in this document" if questions.empty?

      @warnings << "Review the extracted layout because PDF text order may differ from its visual order"
      { questions:, warnings: @warnings.uniq, stats: { questions_count: questions.size, warnings_count: @warnings.uniq.size } }
    rescue PDF::Reader::Error
      raise ApplicationService::Error, "The uploaded file is not a readable PDF document"
    ensure
      @upload.rewind if @upload.respond_to?(:rewind)
    end

    private

    def validate_pdf!
      raise ApplicationService::Error, "A PDF file is required" unless @upload
      raise ApplicationService::Error, "The PDF document exceeds the 25 MB limit" if @upload.size.to_i > MAX_PDF_SIZE
      raise ApplicationService::Error, "Only PDF files are supported" unless File.extname(@upload.original_filename.to_s).downcase == ".pdf"
    end

    def build_reader
      return PDF::Reader.new(@upload.tempfile.path) if @upload.respond_to?(:tempfile) && @upload.tempfile

      PDF::Reader.new(StringIO.new(@upload.read))
    end

    def normal_text_score(page_texts)
      page_texts.sum { |text| recognition_score(text.lines.map(&:strip)) }
    end

    def reversed_text_score(page_texts)
      page_texts.sum { |text| recognition_score(text.lines.map { |line| line.strip.reverse }) }
    end

    def recognition_score(lines)
      lines.count { |line| line.match?(QUESTION_PATTERN) } * 2 +
        lines.count { |line| line.match?(CHOICE_PATTERN) || line.match?(CHOICE_MARKER_PATTERN) }
    end
  end
end
