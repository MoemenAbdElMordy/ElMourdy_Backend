require "cgi"
require "zip"

module Documents
  class DocxBuilder
    CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

    def initialize(title:)
      @title = title
      @body = []
    end

    def heading(text, level: 1)
      size = level == 1 ? 34 : 28
      @body << paragraph_xml(text, bold: true, size:, center: level == 1)
    end

    def paragraph(text, bold: false)
      @body << paragraph_xml(text, bold:)
    end

    def table(headers:, rows:)
      widths = Array.new(headers.size, 9_000 / [ headers.size, 1 ].max)
      table_rows = [ headers, *rows ].map.with_index do |cells, index|
        cell_xml = cells.each_with_index.map do |cell, cell_index|
          "<w:tc><w:tcPr><w:tcW w:w=\"#{widths[cell_index]}\" w:type=\"dxa\"/>#{index.zero? ? '<w:shd w:fill="DDEFE5"/>' : ''}</w:tcPr>#{paragraph_xml(cell, bold: index.zero?)}</w:tc>"
        end.join
        "<w:tr>#{cell_xml}</w:tr>"
      end.join
      @body << "<w:tbl><w:tblPr><w:tblBorders><w:top w:val=\"single\"/><w:left w:val=\"single\"/><w:bottom w:val=\"single\"/><w:right w:val=\"single\"/><w:insideH w:val=\"single\"/><w:insideV w:val=\"single\"/></w:tblBorders><w:bidiVisual/></w:tblPr>#{table_rows}</w:tbl>"
    end

    def render
      Zip::OutputStream.write_buffer do |zip|
        write(zip, "[Content_Types].xml", content_types)
        write(zip, "_rels/.rels", relationships)
        write(zip, "word/document.xml", document)
      end.string
    end

    private

    def write(zip, path, content)
      zip.put_next_entry(path)
      zip.write(content)
    end

    def paragraph_xml(text, bold: false, size: 24, center: false)
      value = CGI.escapeHTML(text.to_s)
      alignment = center ? "<w:jc w:val=\"center\"/>" : "<w:jc w:val=\"right\"/>"
      "<w:p><w:pPr><w:bidi/>#{alignment}<w:spacing w:after=\"120\"/></w:pPr><w:r><w:rPr><w:rtl/>#{bold ? '<w:b/>' : ''}<w:sz w:val=\"#{size}\"/><w:szCs w:val=\"#{size}\"/></w:rPr><w:t xml:space=\"preserve\">#{value}</w:t></w:r></w:p>"
    end

    def document
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        #{paragraph_xml(@title, bold: true, size: 38, center: true)}
        #{@body.join}
        <w:sectPr><w:bidi/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1000"/></w:sectPr>
        </w:body></w:document>
      XML
    end

    def content_types
      '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
    end

    def relationships
      '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    end
  end
end
