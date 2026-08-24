require "nokogiri"
require "stringio"
require "zip"

module Documents
  class ExamDocxParser
    MAX_SIZE = 15.megabytes
    NAMESPACES = {
      "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
      "mc" => "http://schemas.openxmlformats.org/markup-compatibility/2006"
    }.freeze
    QUESTION_PATTERN = /\A\s*[\(\)\-\u2013]*\s*(?:\u0633(?:\u0624\u0627\u0644)?\s*)?[0-9\u0660-\u0669]+\s*[\.\-:\u060C\(\)\u0640\u2013]*\s*(.+)\z/
    CHOICE_LABELS = "\u0623\u0625\u0627ABCDEabcde\u0628\u062C\u062F\u0647"
    CHOICE_PATTERN = /\A\s*([#{CHOICE_LABELS}])\s*[\.\-:\u060C\(\)\u0640\u2013]+\s*(.+)\z/
    CHOICE_MARKER_PATTERN = /(?:\A|\s)([#{CHOICE_LABELS}])\s*[\.\-:\u060C\(\)\u0640\u2013]+\s*/
    ANSWER_PATTERN = /\A\s*(?:\u0627\u0644\u0625\u062C\u0627\u0628\u0629\s*(?:\u0627\u0644\u0635\u062D\u064A\u062D\u0629)?|\u0627\u0644\u062C\u0648\u0627\u0628|answer)\s*[:\-]\s*(.+)\z/i
    EXPLANATION_PATTERN = /\A\s*(?:\u0627\u0644\u0634\u0631\u062D|\u0627\u0644\u062A\u0641\u0633\u064A\u0631|explanation)\s*[:\-]\s*(.+)\z/i

    def initialize(upload)
      @upload = upload
      @warnings = []
    end

    def call
      validate!
      questions = []
      open_archive do |archive|
        document = archive.find_entry("word/document.xml") || raise(ApplicationService::Error, "The Word document is missing its main content")
        xml = document.get_input_stream { |stream| Nokogiri::XML(stream.read) }
        image_count = xml.xpath("//w:drawing|//w:pict", NAMESPACES).size
        @warnings << "#{image_count} embedded image(s) require manual review" if image_count.positive?
        xml.xpath("//w:body/*", NAMESPACES).each do |node|
          if node.name == "tbl"
            parse_table(node, questions)
          elsif node.name == "p"
            parse_paragraph(text_of(node), questions)
          end
        end
      end
      finalize_current(questions)
      raise ApplicationService::Error, "No multiple-choice questions could be recognized in this document" if questions.empty?

      { questions:, warnings: @warnings.uniq, stats: { questions_count: questions.size, warnings_count: @warnings.uniq.size } }
    rescue Zip::Error, Nokogiri::XML::SyntaxError
      raise ApplicationService::Error, "The uploaded file is not a readable DOCX document"
    ensure
      @upload.rewind if @upload.respond_to?(:rewind)
    end

    private

    def open_archive(&block)
      if @upload.respond_to?(:tempfile) && @upload.tempfile
        Zip::File.open(@upload.tempfile.path, &block)
      else
        Zip::File.open_buffer(StringIO.new(@upload.read), &block)
      end
    end

    def validate!
      raise ApplicationService::Error, "A DOCX file is required" unless @upload
      raise ApplicationService::Error, "The Word document exceeds the 15 MB limit" if @upload.size.to_i > MAX_SIZE
      extension = File.extname(@upload.original_filename.to_s).downcase
      raise ApplicationService::Error, "Only DOCX files are supported" unless extension == ".docx"
    end

    def text_of(node)
      node.xpath(".//w:t[not(ancestor::mc:Fallback)]", NAMESPACES).map(&:text).join.strip
    end

    def parse_table(table, questions)
      rows = table.xpath("./w:tr", NAMESPACES).map do |row|
        row.xpath("./w:tc", NAMESPACES).map { |cell| text_of(cell) }.reject(&:blank?)
      end
      rows.each_with_index do |cells, index|
        next if cells.size < 3
        next if index.zero? && cells.first.match?(/\u0627\u0644\u0633\u0624\u0627\u0644|question/i)

        finalize_current(questions)
        answer_cell = cells.drop(1).find { |cell| cell.match?(ANSWER_PATTERN) }
        explanation_cell = cells.drop(1).find { |cell| cell.match?(EXPLANATION_PATTERN) }
        choice_cells = cells.drop(1).reject { |cell| cell.equal?(answer_cell) || cell.equal?(explanation_cell) }
        @current = {
          body: strip_question_label(cells.first), choices: choice_cells.map { |choice| { body: strip_choice_label(choice) } },
          choice_labels: choice_cells.filter_map { |choice| choice.match(CHOICE_PATTERN)&.[](1) },
          answer_hint: answer_cell&.match(ANSWER_PATTERN)&.[](1), explanation: explanation_cell&.match(EXPLANATION_PATTERN)&.[](1).to_s,
          correct_choice_index: nil, source: "table"
        }
        finalize_current(questions)
      end
    end

    def parse_paragraph(text, questions)
      return if text.blank?

      if (match = text.match(QUESTION_PATTERN))
        finalize_current(questions)
        body, choices = split_embedded_choices(match[1])
        @current = question_payload(body)
        append_choices(choices)
      elsif @current && (choices = extract_choices(text)).any?
        append_choices(choices)
      elsif @current && (match = text.match(ANSWER_PATTERN))
        @current[:answer_hint] = match[1].strip
      elsif @current && (match = text.match(EXPLANATION_PATTERN))
        @current[:explanation] = match[1].strip
      elsif @current && @current[:choices].size < 8 && text.length <= 500
        @current[:choices] << { body: strip_choice_label(text) }
        @warnings << "Unlabelled choices were inferred and should be reviewed"
      elsif text.end_with?("\u061F", "?")
        finalize_current(questions)
        @current = question_payload(text)
        @warnings << "An unnumbered question was inferred and should be reviewed"
      end
    end

    def question_payload(body)
      { body: body.strip, choices: [], choice_labels: [], correct_choice_index: nil, explanation: "", source: "paragraph" }
    end

    def split_embedded_choices(text)
      marker = text.match(CHOICE_MARKER_PATTERN)
      return [ text.strip, [] ] unless marker

      [ text[0...marker.begin(0)].strip, extract_choices(text[marker.begin(0)..]) ]
    end

    def extract_choices(text)
      markers = text.to_enum(:scan, CHOICE_MARKER_PATTERN).map { Regexp.last_match }
      markers.each_with_index.filter_map do |marker, index|
        body_end = markers[index + 1]&.begin(0) || text.length
        body = text[marker.end(0)...body_end].to_s.strip
        [ marker[1], body ] if body.present?
      end
    end

    def append_choices(choices)
      choices.each do |label, body|
        @current[:choice_labels] << label
        @current[:choices] << { body: }
      end
    end

    def finalize_current(questions)
      return unless @current

      @current[:choices] = @current[:choices].reject { |choice| choice[:body].blank? }.uniq { |choice| choice[:body] }.first(8)
      if @current[:body].present? && @current[:choices].size >= 2
        resolve_answer_hint(@current)
        @current.delete(:choice_labels)
        @current.delete(:answer_hint)
        questions << @current
      else
        @warnings << "A question with fewer than two choices was skipped"
      end
      @current = nil
    end

    def resolve_answer_hint(question)
      hint = question[:answer_hint].to_s.strip
      return if hint.blank?

      label_index = question[:choice_labels].index { |label| label.casecmp?(hint) }
      body_index = question[:choices].index { |choice| choice[:body].casecmp?(strip_choice_label(hint)) }
      question[:correct_choice_index] = label_index || body_index
    end

    def strip_question_label(text)
      text.to_s.sub(QUESTION_PATTERN, "\\1").strip
    end

    def strip_choice_label(text)
      text.to_s.sub(CHOICE_PATTERN, "\\2").strip
    end
  end
end
