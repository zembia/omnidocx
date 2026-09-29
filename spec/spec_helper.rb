$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "omnidocx"
require "tmpdir"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.include DocxHelper
  config.include RenderHelper, :render

  config.around(:each) do |example|
    Dir.mktmpdir("omnidocx-spec-") do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

def tmp_path(name)
  File.join(@tmp_dir, name)
end
