require "spec_helper"

# Opens the generated documents with LibreOffice, skipped when it's not installed
RSpec.describe Omnidocx::Docx, :render do
  include RenderHelper

  before(:all) { skip "LibreOffice/poppler-utils not installed" unless RenderHelper.available? }

  let(:output) { tmp_path("output.docx") }
  let(:image) { build_png(tmp_path("image.png")) }

  def image_hash(key: nil)
    { path: image, width: 230, height: 234, key: key }.compact
  end

  def fixture(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  context "with a generated document" do
    let(:input) do
      build_docx(tmp_path("in.docx"), paragraphs: ["Hola {{name}}", "{{logo}}", "Fin"],
                                      header: "Cabecera {{h}}", footer: "Pie {{f}}")
    end

    it "shows the replaced text in body, header and footer" do
      step1 = tmp_path("step1.docx")
      step2 = tmp_path("step2.docx")
      described_class.replace_doc_content({ "{{name}}" => "Muñoz" }, input, step1)
      described_class.replace_header_content({ "{{h}}" => "arriba" }, step1, step2)
      described_class.replace_footer_content({ "{{f}}" => "abajo" }, step2, output)

      rendered = render_docx(output)

      expect(rendered.text).to include("Hola Muñoz", "Cabecera arriba", "Pie abajo")
      expect(rendered.text).not_to include("{{name}}", "{{h}}", "{{f}}")
    end

    it "shows every image inserted in a key" do
      described_class.write_images_to_doc([image_hash(key: "{{logo}}"), image_hash(key: "{{logo}}")], input, output)

      rendered = render_docx(output)

      expect(rendered.images).to eq(2)
      expect(rendered.text).to include("Hola {{name}}", "Fin")
      expect(rendered.text).not_to include("{{logo}}")
    end

    it "shows the merged documents on separate pages" do
      other = build_docx(tmp_path("other.docx"), paragraphs: ["Segundo documento"])

      described_class.merge_documents([input, other], output, true)

      rendered = render_docx(output)

      expect(rendered.pages).to eq(2)
      expect(rendered.text).to include("Hola {{name}}", "Segundo documento")
    end

    it "shows an injected OpenXML fragment as separate paragraphs" do
      described_class.replace_doc_content(
        { "{{name}}" => "1. Ítem A</w:t></w:r></w:p><w:p><w:r><w:t>2. Ítem B" }, input, output
      )

      rendered = render_docx(output)

      expect(rendered.text).to include("Hola 1. Ítem A", "2. Ítem B")
      expect(rendered.text).not_to include("&lt;", "</w:t>")
      expect(rendered.text).not_to include("{{name}}")
    end
  end

  context "with documents created in a word processor" do
    it "replaces a key in the middle of a text" do
      described_class.replace_doc_content({ "{{i1}}" => "Mundo" }, fixture("text_and_key.docx"), output)

      expect(render_docx(output).text).to include("Hola como estás Mundo")
    end

    it "replaces a paragraph with only a key by an image" do
      described_class.write_images_to_doc([image_hash(key: "{{i1}}")], fixture("only_key.docx"), output)

      rendered = render_docx(output)

      expect(rendered.images).to eq(1)
      expect(rendered.text).not_to include("{{i1}}")
    end

    it "keeps the other paragraphs when replacing a key by an image" do
      described_class.write_images_to_doc([image_hash(key: "{{i1}}")], fixture("text_and_key_separate.docx"), output)

      rendered = render_docx(output)

      expect(rendered.images).to eq(1)
      expect(rendered.text).to include("Hola hola")
      expect(rendered.text).not_to include("{{i1}}")
    end

    it "merges them" do
      described_class.merge_documents([fixture("text_and_key.docx"), fixture("text_and_key_separate.docx")], output, false)

      rendered = render_docx(output)

      expect(rendered.text).to include("Hola como estás {{i1}}", "Hola hola")
    end
  end
end
