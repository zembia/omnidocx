require "zip"
require "nokogiri"
require "zlib"

# Builds minimal .docx files on the fly so specs don't depend on binary fixtures
module DocxHelper
  W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

  # directories: adds directory entries like "word/", as some word processors do
  # styles: extra <w:style> elements for styles.xml
  def build_docx(path, paragraphs: [], header: nil, footer: nil, directories: false, styles: "")
    Zip::OutputStream.open(path) do |zos|
      %w[_rels/ word/ word/_rels/].each { |dir| zos.put_next_entry(dir) } if directories

      zos.put_next_entry("[Content_Types].xml")
      zos.print content_types_xml(header: header, footer: footer)

      zos.put_next_entry("_rels/.rels")
      zos.print root_rels_xml

      zos.put_next_entry("word/_rels/document.xml.rels")
      zos.print document_rels_xml(header: header, footer: footer)

      zos.put_next_entry("word/document.xml")
      zos.print document_xml(paragraphs, header: header, footer: footer)

      zos.put_next_entry("word/styles.xml")
      zos.print styles_xml(styles)

      if header
        zos.put_next_entry("word/header1.xml")
        zos.print header_footer_xml("hdr", header)
      end

      if footer
        zos.put_next_entry("word/footer1.xml")
        zos.print header_footer_xml("ftr", footer)
      end
    end
    path
  end

  # 1x1 PNG
  def build_png(path)
    chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    png = "\x89PNG\r\n\x1a\n".b
    png << chunk.call("IHDR", [1, 1, 8, 2, 0, 0, 0].pack("NNCCCCC"))
    png << chunk.call("IDAT", Zlib::Deflate.deflate("\x00\xff\x00\x00".b))
    png << chunk.call("IEND", "")
    File.binwrite(path, png)
    path
  end

  def read_zip_entry(path, entry)
    Zip::File.open(path) { |zip| zip.read(entry).force_encoding("UTF-8") }
  end

  def zip_entry_names(path)
    Zip::File.open(path) { |zip| zip.entries.map(&:name) }
  end

  def document_body(path)
    Nokogiri::XML(read_zip_entry(path, "word/document.xml")).at_xpath("//w:body", "w" => W_NS)
  end

  def paragraph_texts(path)
    document_body(path).xpath("./w:p", "w" => W_NS).map do |p|
      p.xpath(".//w:t", "w" => W_NS).map(&:content).join
    end
  end

  private

  # a paragraph given as an array is written as one run per element,
  # like Word does when a key gets split across runs
  def paragraph_xml(text)
    runs = Array(text).map { |t| %(<w:r><w:t xml:space="preserve">#{t.encode(xml: :text)}</w:t></w:r>) }
    "<w:p>#{runs.join}</w:p>"
  end

  def document_xml(paragraphs, header:, footer:)
    section = ""
    section << %(<w:headerReference w:type="default" r:id="rIdHeader"/>) if header
    section << %(<w:footerReference w:type="default" r:id="rIdFooter"/>) if footer
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document xmlns:w="#{W_NS}" xmlns:r="#{R_NS}" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>#{paragraphs.map { |t| paragraph_xml(t) }.join}<w:sectPr>#{section}</w:sectPr></w:body></w:document>
    XML
  end

  def header_footer_xml(root, text)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:#{root} xmlns:w="#{W_NS}">#{paragraph_xml(text)}</w:#{root}>
    XML
  end

  def content_types_xml(header:, footer:)
    overrides = ""
    overrides << %(<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>) if header
    overrides << %(<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>) if footer
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>#{overrides}</Types>
    XML
  end

  def root_rels_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    XML
  end

  def document_rels_xml(header:, footer:)
    rels = ""
    rels << %(<Relationship Id="rIdHeader" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>) if header
    rels << %(<Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>) if footer
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>#{rels}</Relationships>
    XML
  end

  def styles_xml(extra)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:styles xmlns:w="#{W_NS}"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>#{extra}</w:styles>
    XML
  end
end
