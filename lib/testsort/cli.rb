module Testsort
  class CLI < Thor
    Dir[File.expand_path 'commands/*.rb', __dir__].each do |file|
      class_eval File.read(file), file
    end
  end
end
