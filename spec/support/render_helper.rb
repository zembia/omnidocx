require "open3"
require "tmpdir"

# Renders a .docx to PDF with LibreOffice to check it opens and shows the expected content
module RenderHelper
  TOOLS = %w[soffice pdftotext pdfinfo pdfimages].freeze

  def self.available?
    TOOLS.all? { |tool| system("which #{tool} > /dev/null 2>&1") }
  end

  Rendered = Struct.new(:text, :pages, :images, keyword_init: true)

  def render_docx(path)
    out_dir = File.join(File.dirname(path), "pdf")
    Dir.mktmpdir("omnidocx-lo-profile-") do |profile|
      # own profile per call so conversions don't clash with a running LibreOffice
      run!("soffice", "-env:UserInstallation=file://#{profile}", "--headless",
           "--convert-to", "pdf", "--outdir", out_dir, path)
    end

    pdf = File.join(out_dir, File.basename(path, ".docx") + ".pdf")
    raise "LibreOffice could not render #{File.basename(path)}" unless File.exist?(pdf)

    Rendered.new(
      text: run!("pdftotext", "-layout", pdf, "-").gsub(/[ \t]+/, " "),
      pages: run!("pdfinfo", pdf)[/^Pages:\s+(\d+)/, 1].to_i,
      # transparent images also list their alpha mask (smask), only count the images
      images: run!("pdfimages", "-list", pdf).lines.drop(2).count { |line| line.split[2] == "image" }
    )
  end

  private

  def run!(*cmd)
    out, err, status = Open3.capture3(*cmd)
    raise "#{cmd.first} failed: #{err}" unless status.success?
    out
  end
end
