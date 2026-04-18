module Testsort
  module IOHelper
    class << self
      def exclusively_locked_dir_access(path)
        directory = File.open(path)
        directory.flock(File::LOCK_EX)
        yield
      ensure
        directory.flock(File::LOCK_UN)
      end

      def read_json(path)
        return nil unless File.exist?(path)

        json = File.read(path)

        return nil if json.strip.empty?

        JSON.parse(json)
      end

      def write_json(path, json)
        File.open(path, 'w+') do |f|
          f.puts JSON.pretty_generate(json)
        end
      end
    end
  end
end
