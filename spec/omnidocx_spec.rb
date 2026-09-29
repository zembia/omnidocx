require "spec_helper"

RSpec.describe Omnidocx do
  it "has a version number" do
    expect(Omnidocx::VERSION).not_to be nil
  end
end

RSpec.describe Omnidocx::Docx do
  let(:output) { tmp_path("output.docx") }
  let(:image) { build_png(tmp_path("image.png")) }

  def drawings(path)
    document_body(path).xpath(".//w:drawing", "w" => DocxHelper::W_NS)
  end

  def fixture(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def image_hash(key: nil, width: 230, height: 234)
    { path: image, width: width, height: height, key: key }.compact
  end

  describe ".replace_doc_content" do
    it "replaces the keys in the document body" do
      input = build_docx(tmp_path("in.docx"), paragraphs: ["Hola {{name}}", "Total: {{amount}}"])

      described_class.replace_doc_content({ "{{name}}" => "Mundo", "{{amount}}" => "100" }, input, output)

      expect(paragraph_texts(output)).to eq(["Hola Mundo", "Total: 100"])
    end

    it "keeps multibyte characters intact" do
      input = build_docx(tmp_path("in.docx"), paragraphs: ["Señor {{name}}"])

      described_class.replace_doc_content({ "{{name}}" => "Muñoz" }, input, output)

      expect(paragraph_texts(output)).to eq(["Señor Muñoz"])
    end

    it "replaces keys in a document created in a word processor" do
      described_class.replace_doc_content({ "{{i1}}" => "Mundo" }, fixture("text_and_key.docx"), output)

      expect(paragraph_texts(output)).to include("Hola como estás Mundo")
    end

    it "replaces keys split across runs" do
      pending "the key is matched against the raw XML, so it isn't found when Word splits it in several runs"
      input = build_docx(tmp_path("in.docx"), paragraphs: [["Hola {{na", "me}}"]])

      described_class.replace_doc_content({ "{{name}}" => "Mundo" }, input, output)

      expect(paragraph_texts(output)).to eq(["Hola Mundo"])
    end

    it "copies the rest of the entries unchanged" do
      input = build_docx(tmp_path("in.docx"), paragraphs: ["x"])

      described_class.replace_doc_content({}, input, output)

      expect(zip_entry_names(output)).to match_array(zip_entry_names(input))
      expect(read_zip_entry(output, "word/styles.xml")).to eq(read_zip_entry(input, "word/styles.xml"))
    end
  end

  describe ".replace_header_content" do
    it "replaces the keys in the header only" do
      input = build_docx(tmp_path("in.docx"), paragraphs: ["{{key}}"], header: "Header {{key}}")

      described_class.replace_header_content({ "{{key}}" => "OK" }, input, output)

      expect(read_zip_entry(output, "word/header1.xml")).to include("Header OK")
      expect(paragraph_texts(output)).to eq(["{{key}}"])
    end
  end

  describe ".replace_footer_content" do
    it "replaces the keys in the footer only" do
      input = build_docx(tmp_path("in.docx"), paragraphs: ["{{key}}"], footer: "Footer {{key}}")

      described_class.replace_footer_content({ "{{key}}" => "OK" }, input, output)

      expect(read_zip_entry(output, "word/footer1.xml")).to include("Footer OK")
      expect(paragraph_texts(output)).to eq(["{{key}}"])
    end
  end

  describe ".write_images_to_doc" do
    let(:input) { build_docx(tmp_path("in.docx"), paragraphs: ["Intro", "{{logo}}", "Fin"]) }

    it "adds the image file, relationship and content type" do
      described_class.write_images_to_doc([image_hash], input, output)

      expect(zip_entry_names(output)).to include("word/media/image20.png")

      rels = Nokogiri::XML(read_zip_entry(output, "word/_rels/document.xml.rels"))
      rel = rels.css("Relationship").find { |r| r["Id"] == "rid20" }
      expect(rel["Target"]).to eq("media/image20.png")
      expect(rel["Type"]).to eq(Omnidocx::Docx::MEDIA_TYPE)

      types = Nokogiri::XML(read_zip_entry(output, "[Content_Types].xml"))
      expect(types.css("Default").map { |d| [d["Extension"], d["ContentType"]] }).to include(["png", "image/png"])
    end

    it "appends the image at the end of the body when no key is given" do
      described_class.write_images_to_doc([image_hash], input, output)

      body = document_body(output)
      expect(paragraph_texts(output)).to eq(["Intro", "{{logo}}", "Fin", ""])
      expect(body.element_children.last.name).to eq("sectPr")
      expect(drawings(output).size).to eq(1)
    end

    it "sets the size in EMUs from width, height and dpi" do
      described_class.write_images_to_doc([image_hash(width: 230, height: 234)], input, output)

      extent = document_body(output).at_xpath(".//wp:extent", Omnidocx::Docx::NAMESPACES)
      expect(extent["cx"]).to eq((230 / 115 * Omnidocx::Docx::EMUSPERINCH).to_s)
      expect(extent["cy"]).to eq((234 / 117 * Omnidocx::Docx::EMUSPERINCH).to_s)
    end

    it "replaces the paragraph containing the key with the image" do
      described_class.write_images_to_doc([image_hash(key: "{{logo}}")], input, output)

      expect(paragraph_texts(output)).to eq(["Intro", "", "Fin"])
      expect(drawings(output).size).to eq(1)
    end

    it "inserts every image of the same key in order" do
      second = build_png(tmp_path("second.png"))
      images = [image_hash(key: "{{logo}}"), image_hash(key: "{{logo}}").merge(path: second)]

      described_class.write_images_to_doc(images, input, output)

      expect(paragraph_texts(output)).to eq(["Intro", "", "", "Fin"])
      embeds = document_body(output).xpath(".//a:blip", Omnidocx::Docx::NAMESPACES).map { |b| b["r:embed"] }
      expect(embeds).to eq(%w[rid20 rid21])
    end

    it "replaces every paragraph containing the key" do
      input = build_docx(tmp_path("in.docx"), paragraphs: ["{{logo}}", "medio", "{{logo}}"])

      described_class.write_images_to_doc([image_hash(key: "{{logo}}")], input, output)

      expect(paragraph_texts(output)).to eq(["", "medio", ""])
      expect(drawings(output).size).to eq(2)
    end

    it "handles different keys independently" do
      input = build_docx(tmp_path("in.docx"), paragraphs: ["{{a}}", "{{b}}"])

      described_class.write_images_to_doc([image_hash(key: "{{a}}"), image_hash(key: "{{b}}")], input, output)

      expect(paragraph_texts(output)).to eq(["", ""])
      expect(drawings(output).size).to eq(2)
    end

    it "does not support image URLs" do
      images = [image_hash.merge(path: "https://example.com/image.png")]

      expect { described_class.write_images_to_doc(images, input, output) }.to raise_error(Errno::ENOENT)
    end

    it "replaces a key in a document created in a word processor" do
      input = fixture("text_and_key_separate.docx")

      described_class.write_images_to_doc([image_hash(key: "{{i1}}")], input, output)

      expect(paragraph_texts(output)).to eq(["Hola hola", ""])
      expect(drawings(output).size).to eq(1)
    end

    it "leaves the document untouched when the key is not found" do
      described_class.write_images_to_doc([image_hash(key: "{{missing}}")], input, output)

      expect(paragraph_texts(output)).to eq(["Intro", "{{logo}}", "Fin"])
      expect(drawings(output)).to be_empty
    end
  end

  describe ".merge_documents" do
    let(:doc1) { build_docx(tmp_path("doc1.docx"), paragraphs: ["Primero"]) }
    let(:doc2) { build_docx(tmp_path("doc2.docx"), paragraphs: ["Segundo", "Tercero"]) }

    it "requires at least two documents" do
      expect(described_class.merge_documents([doc1], output, false)).to eq("Pass atleast two documents to be merged")
      expect(File).not_to exist(output)
    end

    it "appends the body of the following documents to the first one" do
      described_class.merge_documents([doc1, doc2], output, false)

      expect(paragraph_texts(output)).to eq(["Primero", "Segundo", "Tercero"])
      expect(document_body(output).element_children.last.name).to eq("sectPr")
    end

    it "adds a page break between documents when requested" do
      described_class.merge_documents([doc1, doc2], output, true)

      breaks = document_body(output).xpath(".//w:br[@w:type='page']", "w" => DocxHelper::W_NS)
      expect(breaks.size).to eq(1)
      expect(paragraph_texts(output)).to eq(["Primero", "", "Segundo", "Tercero"])
    end
  end
end
